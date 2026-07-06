import Foundation

// MARK: - Result model

/// Outcome of one claude-driven PR publish run. `created` carries what the UI
/// needs to link the PR; `failed` carries a user-facing message.
enum PRCreateOutcome: Sendable, Equatable {
    case created(prNumber: Int, url: URL, summary: String)
    case nothingToDo(summary: String)
    case failed(String)
}

// MARK: - Output parsing (pure)

enum PRCreateParsing {
    private struct Raw: Decodable {
        let outcome: String
        let pr_number: Int?
        let pr_url: String?
        let summary: String?
    }

    /// Parses the final result text of a publish run into an outcome. Returns
    /// nil when no valid outcome JSON can be recovered — callers MUST treat nil
    /// as "could not confirm" and surface a failure, never a success.
    static func parse(text: String) -> PRCreateOutcome? {
        guard let objectJSON = ClaudeReviewParsing.lastJSONObject(in: text),
              let data = objectJSON.data(using: .utf8),
              let raw = try? JSONDecoder().decode(Raw.self, from: data)
        else { return nil }
        switch raw.outcome {
        case "created":
            // Strict: a "created" claim without a usable number + URL is not
            // trustworthy enough to render a clickable pill.
            guard let n = raw.pr_number, let u = raw.pr_url, !u.isEmpty,
                  let url = URL(string: u)
            else { return nil }
            return .created(prNumber: n, url: url, summary: raw.summary ?? "")
        case "nothing_to_do":
            return .nothingToDo(summary: raw.summary ?? "")
        case "failed":
            return .failed(raw.summary ?? "claude 回報失敗但未提供原因。")
        default:
            return nil
        }
    }
}
