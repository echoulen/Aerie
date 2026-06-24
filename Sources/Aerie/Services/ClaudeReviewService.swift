import Foundation

// MARK: - Result models

/// Claude's overall judgement on a PR.
enum ClaudeReviewVerdict: String, Sendable, Equatable {
    case approve
    case issuesFound
}

/// A parsed Claude review: the verdict, a one-paragraph summary, any concrete
/// issues, plus the raw stdout for debugging.
struct ClaudeReview: Sendable, Equatable {
    let verdict: ClaudeReviewVerdict
    let summary: String
    let issues: [String]
    let raw: String
}

/// Outcome of attempting an AI review. `.failed` carries a user-facing message.
enum ClaudeReviewOutcome: Sendable, Equatable {
    case success(ClaudeReview)
    case failed(String)
}

// MARK: - Prompt assembly (pure)

enum ClaudeReviewPrompt {
    /// Renders the PR's changed files into a plain-text diff blob for the prompt.
    static func diffText(files: [PRFileChange]) -> String {
        files.map { file in
            let header = "### \(file.filename) [\(file.status)] +\(file.additions)/-\(file.deletions)"
            let body = file.patch ?? "(no textual diff — binary or too large to show)"
            return "\(header)\n\(body)"
        }.joined(separator: "\n\n")
    }

    /// Builds the `claude -p` prompt. Asks for a strict JSON verdict so the
    /// output is machine-parseable; `verdict` is `approve` only when there are
    /// no MAJOR problems.
    static func build(
        owner: String, repo: String, number: Int,
        title: String, author: String, sourceBranch: String, diff: String
    ) -> String {
        """
        You are reviewing a GitHub pull request for \(owner)/\(repo). You may read \
        files in the current working directory (read-only) for additional context.

        PR #\(number): \(title)
        Author: \(author)
        Branch: \(sourceBranch)

        Review the diff below for MAJOR problems only: correctness bugs, security \
        vulnerabilities, breaking changes, or data loss. Style nits and minor \
        preferences are NOT major.

        Diff:
        \(diff)

        Respond with your analysis, then end your message with a single JSON object \
        on its own, exactly in this shape:
        {"verdict": "approve" | "issues_found", "summary": "<one paragraph>", "issues": ["<issue>", ...]}

        Use "verdict": "approve" ONLY if there are no major problems. If you find \
        any major problem, use "issues_found" and list each in "issues".
        """
    }
}

// MARK: - Output parsing (pure)

enum ClaudeReviewParsing {
    private struct Envelope: Decodable { let result: String }
    private struct Raw: Decodable {
        let verdict: String
        let summary: String
        let issues: [String]?
    }

    /// Parses `claude -p --output-format json` stdout into a `ClaudeReview`.
    /// Returns nil when no valid verdict JSON can be recovered — callers MUST
    /// treat nil as "could not review" and never approve on it.
    static func parse(stdout: String) -> ClaudeReview? {
        // `--output-format json` wraps the assistant text in an envelope with a
        // `result` field; if that decode fails (e.g. a bare JSON fixture), fall
        // back to treating the whole stdout as the text to scan.
        let text = decodeEnvelopeResult(stdout) ?? stdout
        guard let objectJSON = lastJSONObject(in: text),
              let data = objectJSON.data(using: .utf8),
              let raw = try? JSONDecoder().decode(Raw.self, from: data),
              let verdict = mapVerdict(raw.verdict)
        else { return nil }
        return ClaudeReview(
            verdict: verdict,
            summary: raw.summary,
            issues: raw.issues ?? [],
            raw: stdout
        )
    }

    private static func decodeEnvelopeResult(_ stdout: String) -> String? {
        guard let data = stdout.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        return env.result
    }

    /// Extracts the last balanced `{…}` object in the text — the verdict JSON
    /// Claude is asked to put at the end of its message. Scanning from the final
    /// `}` backwards (rather than first-`{`/last-`}`) means stray braces in the
    /// prose before the JSON don't corrupt the span.
    private static func lastJSONObject(in text: String) -> String? {
        guard let close = text.lastIndex(of: "}") else { return nil }
        var depth = 0
        var idx = close
        while true {
            let ch = text[idx]
            if ch == "}" { depth += 1 }
            else if ch == "{" {
                depth -= 1
                if depth == 0 { return String(text[idx...close]) }
            }
            if idx == text.startIndex { break }
            idx = text.index(before: idx)
        }
        return nil
    }

    private static func mapVerdict(_ s: String) -> ClaudeReviewVerdict? {
        switch s {
        case "approve": return .approve
        case "issues_found": return .issuesFound
        default: return nil
        }
    }
}

// MARK: - Service

protocol ClaudeReviewService: Sendable {
    func review(
        owner: String, repo: String, number: Int,
        title: String, author: String, sourceBranch: String,
        diff: String, localPath: URL
    ) async -> ClaudeReviewOutcome
}

struct LiveClaudeReviewService: ClaudeReviewService {
    private let runner: SubprocessRunner
    private let timeout: TimeInterval

    init(runner: SubprocessRunner = LiveSubprocessRunner(), timeout: TimeInterval = 120) {
        self.runner = runner
        self.timeout = timeout
    }

    func review(
        owner: String, repo: String, number: Int,
        title: String, author: String, sourceBranch: String,
        diff: String, localPath: URL
    ) async -> ClaudeReviewOutcome {
        // 1. Claude installed? A throw (missing PATH entry, etc.) or a non-zero /
        //    empty result all mean "can't run claude".
        let probe = try? await runner.run("which", ["claude"])
        guard let probe, probe.2 == 0,
              !probe.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .failed("找不到 claude CLI。請先安裝 Claude Code 並確認可在終端機執行 `claude`。")
        }

        // 2. cwd = repo checkout when it exists on disk, else nil (pure-diff mode).
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: localPath.path, isDirectory: &isDir)
        let cwd: URL? = (exists && isDir.boolValue) ? localPath : nil

        // 3. Build prompt + args.
        let prompt = ClaudeReviewPrompt.build(
            owner: owner, repo: repo, number: number,
            title: title, author: author, sourceBranch: sourceBranch, diff: diff)
        let args = ["-p", prompt, "--output-format", "json", "--allowedTools", "Read,Grep,Glob"]

        // 4. Run with a timeout. A timed-out claude is read-only and harmless;
        //    we just stop waiting and report it.
        do {
            let runner = self.runner
            let (out, err, code) = try await withTimeout(seconds: timeout) {
                try await runner.run("claude", args, cwd: cwd)
            }
            guard code == 0 else {
                let detail = err.isEmpty ? out : err
                return .failed("AI Review 失敗(exit \(code)):\(detail.prefix(300))")
            }
            guard let review = ClaudeReviewParsing.parse(stdout: out) else {
                return .failed("無法解析 Claude 的回覆,為求保險不予 approve。")
            }
            return .success(review)
        } catch is ClaudeReviewTimeout {
            return .failed("AI Review 逾時(超過 \(Int(timeout)) 秒)。")
        } catch {
            return .failed("AI Review 發生錯誤:\(error.localizedDescription)")
        }
    }
}

private struct ClaudeReviewTimeout: Error {}

/// Runs `work`, throwing `ClaudeReviewTimeout` if it doesn't finish in time.
private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ClaudeReviewTimeout()
        }
        defer { group.cancelAll() }
        let result = try await group.next()!
        return result
    }
}
