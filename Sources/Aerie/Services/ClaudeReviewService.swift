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
