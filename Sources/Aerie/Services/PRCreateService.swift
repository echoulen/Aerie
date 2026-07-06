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

// MARK: - Prompt assembly (pure)

enum PRCreatePrompt {
    /// One human-readable line describing the working tree, injected into the
    /// template as {{STATUS_SUMMARY}}. Claude re-verifies with `git status`
    /// anyway; this just orients it (and makes prompts reproducible in tests).
    static func statusSummary(_ s: LocalGitStatus?) -> String {
        guard let s else { return "clean · in sync with origin" }
        var bits: [String] = []
        if s.isDirty { bits.append("working tree dirty (\(s.dirtyFileCount) files)") }
        if s.aheadOfDefault > 0 { bits.append("\(s.aheadOfDefault) ahead of default") }
        if s.behindOfDefault > 0 { bits.append("\(s.behindOfDefault) behind default") }
        if s.unpushedCommits > 0 { bits.append("\(s.unpushedCommits) unpushed") }
        return bits.isEmpty ? "clean · in sync with origin" : bits.joined(separator: " · ")
    }

    /// Substitutes the template's {{…}} variables. Unknown tokens are left
    /// as-is — a custom template may legitimately contain literal braces.
    static func render(
        template: String,
        owner: String, repo: String,
        defaultBranch: String, currentBranch: String,
        statusSummary: String
    ) -> String {
        template
            .replacingOccurrences(of: "{{OWNER}}", with: owner)
            .replacingOccurrences(of: "{{REPO}}", with: repo)
            .replacingOccurrences(of: "{{DEFAULT_BRANCH}}", with: defaultBranch)
            .replacingOccurrences(of: "{{CURRENT_BRANCH}}", with: currentBranch)
            .replacingOccurrences(of: "{{STATUS_SUMMARY}}", with: statusSummary)
    }
}

/// The built-in PR publish template shipped with Aerie — used whenever the
/// user hasn't saved a custom template in Settings → Pull Requests.
enum DefaultPRPublishTemplate {
    /// Resolves the effective template: the stored custom one when present and
    /// non-blank, else the built-in default.
    static func resolve(stored: String?) -> String {
        guard let stored,
              !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return text }
        return stored
    }

    static let text = """
    You are publishing local work in the repository {{OWNER}}/{{REPO}} as a \
    GitHub pull request, working in the current directory.

    Known state (re-verify before acting): default branch {{DEFAULT_BRANCH}}, \
    current branch {{CURRENT_BRANCH}}, {{STATUS_SUMMARY}}.

    Inspect the actual state first (`git status`, `git log --oneline -10`, \
    `git diff`), then adapt:
    1. If there is genuinely nothing to publish (clean tree, no unpushed \
    commits, nothing ahead of {{DEFAULT_BRANCH}}), stop and report outcome \
    "nothing_to_do".
    2. If you are on {{DEFAULT_BRANCH}} and there is work to publish, create a \
    new branch first, named from the change content with a conventional prefix \
    (feat/…, fix/…, chore/…).
    3. If the working tree is dirty, stage everything and commit with a \
    conventional-commit message written from the actual diff.
    4. Push with `git push -u origin <branch>`.
    5. Open the PR with `gh pr create` — write a concise title and a body that \
    summarises what changed and why. Do not enable auto-merge; do not approve \
    or merge the PR.

    Rules:
    - Never force-push, never rebase, never amend commits that are already \
    pushed.
    - Never push directly to {{DEFAULT_BRANCH}}.
    - If a step fails and you cannot recover, report outcome "failed" with the \
    reason in "summary".

    End your message with a single JSON object on its own, exactly in this \
    shape:
    {"outcome": "created" | "nothing_to_do" | "failed", "pr_number": <int or null>, "pr_url": "<url or null>", "summary": "<一句繁體中文摘要>"}
    Use "created" ONLY if `gh pr create` succeeded, with the real PR number \
    and URL taken from its output.
    """
}

