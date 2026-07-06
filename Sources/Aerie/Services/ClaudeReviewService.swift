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
        {"verdict": "approve" | "issues_found", "summary": "<concise markdown — short \"- \" bullet points of the key findings (and a final \"結論:\" bullet), NOT one long run-on paragraph; this string is shown verbatim in a GitHub PR comment, so write it as readable markdown>", "issues": ["<issue>", ...]}

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
    /// Internal (not private): `PRCreateParsing` shares this scanner.
    static func lastJSONObject(in text: String) -> String? {
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

// MARK: - Stream parsing (pure)

/// One parsed line of `claude --output-format stream-json`.
enum ClaudeStreamEvent: Equatable {
    case progress(String)     // a human-readable progress line to show
    case finalResult(String)  // the `result` event's text (feed to ClaudeReviewParsing)
    case ignored              // system/hook/tool_result/noise
}

enum ClaudeStreamParsing {
    private struct Line: Decodable {
        let type: String
        let result: String?
        let message: Message?
        struct Message: Decodable { let content: [Block]? }
        struct Block: Decodable {
            let type: String
            let text: String?
            let name: String?
            let input: [String: JSONScalar]?
        }
    }
    /// Minimal decoder for tool_use `input` values we care about (strings).
    private enum JSONScalar: Decodable {
        case string(String), other
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .string(s) } else { self = .other }
        }
        var string: String? { if case .string(let s) = self { return s }; return nil }
    }

    static func parseLine(_ line: String) -> ClaudeStreamEvent {
        guard let data = line.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(Line.self, from: data)
        else { return .ignored }

        switch parsed.type {
        case "result":
            if let r = parsed.result { return .finalResult(r) }
            return .ignored
        case "assistant":
            for block in parsed.message?.content ?? [] {
                if block.type == "text" {
                    let t = (block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return .progress(t) }
                } else if block.type == "tool_use" {
                    return .progress(describeTool(name: block.name ?? "?", input: block.input ?? [:]))
                }
            }
            return .ignored
        default:
            // system (incl. hook_*), user (tool_result), anything else
            return .ignored
        }
    }

    private static func describeTool(name: String, input: [String: JSONScalar]) -> String {
        switch name {
        case "Read":  return "Read \(input["file_path"]?.string ?? "")".trimmingCharacters(in: .whitespaces)
        case "Grep":  return "Grep \"\(input["pattern"]?.string ?? "")\""
        case "Glob":  return "Glob \(input["pattern"]?.string ?? "")".trimmingCharacters(in: .whitespaces)
        default:      return "Using \(name)"
        }
    }
}

// MARK: - Service

protocol ClaudeReviewService: Sendable {
    func review(
        owner: String, repo: String, number: Int,
        title: String, author: String, sourceBranch: String,
        diff: String, localPath: URL,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> ClaudeReviewOutcome
}

struct LiveClaudeReviewService: ClaudeReviewService {
    private let runner: SubprocessRunner
    private let idleTimeout: TimeInterval
    private let totalTimeout: TimeInterval

    init(runner: SubprocessRunner = LiveSubprocessRunner(),
         idleTimeout: TimeInterval = 600, totalTimeout: TimeInterval = 600) {
        self.runner = runner
        self.idleTimeout = idleTimeout
        self.totalTimeout = totalTimeout
    }

    func review(
        owner: String, repo: String, number: Int,
        title: String, author: String, sourceBranch: String,
        diff: String, localPath: URL,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> ClaudeReviewOutcome {
        // 1. Claude installed?
        let probe = try? await runner.run("which", ["claude"])
        guard let probe, probe.2 == 0,
              !probe.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failed("找不到 claude CLI。請先安裝 Claude Code 並確認可在終端機執行 `claude`。") }

        // 2. cwd = repo checkout when present.
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: localPath.path, isDirectory: &isDir)
        let cwd: URL? = (exists && isDir.boolValue) ? localPath : nil

        // 3. Prompt + streaming args.
        let prompt = ClaudeReviewPrompt.build(
            owner: owner, repo: repo, number: number,
            title: title, author: author, sourceBranch: sourceBranch, diff: diff)
        let args = ["-p", prompt, "--output-format", "stream-json", "--verbose",
                    "--allowedTools", "Read,Grep,Glob"]

        // 4. Stream with idle + total watchdog. Each shown line bumps the activity
        //    clock; the watchdog cancels (→ terminate process) if idle or total
        //    elapses. A box collects the final result text.
        let activity = ActivityClock()
        let finalText = TextBox()
        let runner = self.runner
        let idle = idleTimeout, total = totalTimeout

        return await withTaskGroup(of: ReviewStep.self) { group -> ClaudeReviewOutcome in
            group.addTask {
                do {
                    let code = try await runner.stream("claude", args, cwd: cwd) { line in
                        switch ClaudeStreamParsing.parseLine(line) {
                        case .progress(let s): activity.bump(); onLine(s)
                        case .finalResult(let t): activity.bump(); finalText.set(t)
                        case .ignored: break
                        }
                    }
                    return .finished(code)
                } catch is CancellationError { return .cancelled }
                catch { return .error(error.localizedDescription) }
            }
            group.addTask {
                let start = ContinuousClock.now
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return .cancelled }
                    if activity.secondsSinceLast() > idle { return .timedOutIdle }
                    if start.duration(to: .now) > .seconds(total) { return .timedOutTotal }
                }
            }
            let first = await group.next()!
            group.cancelAll()
            for await _ in group {}   // drain

            switch first {
            case .timedOutIdle:
                return .failed("AI Review 已 \(Int(idle)) 秒沒有新進度,可能卡住了。")
            case .timedOutTotal:
                return .failed("AI Review 超過 \(Int(total/60)) 分鐘上限。")
            case .cancelled:
                return .failed("AI Review 已取消。")
            case .error(let m):
                return .failed("AI Review 發生錯誤:\(m)")
            case .finished(let code):
                guard code == 0 else { return .failed("AI Review 失敗(exit \(code))。") }
                guard let review = ClaudeReviewParsing.parse(stdout: finalText.get()) else {
                    return .failed("無法解析 Claude 的回覆,為求保險不予 approve。")
                }
                return .success(review)
            }
        }
    }
}

private enum ReviewStep: Sendable {
    case finished(Int32), timedOutIdle, timedOutTotal, cancelled, error(String)
}

/// Tracks the time of the last activity, thread-safe.
private final class ActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ContinuousClock.now
    func bump() { lock.lock(); last = ContinuousClock.now; lock.unlock() }
    func secondsSinceLast() -> Double {
        lock.lock(); defer { lock.unlock() }
        let d = last.duration(to: .now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

/// Thread-safe holder for the final result text.
private final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func set(_ t: String) { lock.lock(); text = t; lock.unlock() }
    func get() -> String { lock.lock(); defer { lock.unlock() }; return text }
}
