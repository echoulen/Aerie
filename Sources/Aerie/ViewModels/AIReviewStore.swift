import SwiftUI
import Observation

/// AI-review lifecycle for one PR. `.running` carries accumulated progress lines;
/// `.done` carries the review plus which account acted (approve/comment).
enum AIReviewPhase: Equatable {
    case idle
    case running([String])
    case done(ClaudeReview, actedAs: String?)
    case failed(String)
}

/// Owns AI-review execution + state for ALL PRs, keyed by a STABLE per-PR key
/// (repo id + PR number), so a review survives the review screen being torn down
/// and rebuilt (Back → re-enter). `PullRequest.id` is a fresh UUID on every API
/// fetch, so it must NOT be the key. Held by `MainShell`, not the per-screen VM.
@MainActor
@Observable
final class AIReviewStore {
    private(set) var phases: [String: AIReviewPhase] = [:]
    private var running: Set<String> = []
    private let maxLines = 200

    private let loadFiles: (PRRow) async throws -> [PRFileChange]
    private let runReview: (PRRow, String, @escaping @Sendable (String) -> Void) async -> ClaudeReviewOutcome
    private let resolveApprover: (PRRow) async -> GitHubAccount?
    private let approve: (PRRow, GitHubAccount, String) async -> String?
    private let comment: (PRRow, GitHubAccount, String) async -> String?

    init(
        loadFiles: @escaping (PRRow) async throws -> [PRFileChange],
        runReview: @escaping (PRRow, String, @escaping @Sendable (String) -> Void) async -> ClaudeReviewOutcome,
        resolveApprover: @escaping (PRRow) async -> GitHubAccount?,
        approve: @escaping (PRRow, GitHubAccount, String) async -> String?,
        comment: @escaping (PRRow, GitHubAccount, String) async -> String?
    ) {
        self.loadFiles = loadFiles
        self.runReview = runReview
        self.resolveApprover = resolveApprover
        self.approve = approve
        self.comment = comment
    }

    /// Stable per-PR key. `PullRequest.id` is a fresh UUID on every API fetch, so
    /// it can't be the key (Back → refresh → re-fetch changes it). The repo's
    /// persisted id plus the PR number is stable across refreshes.
    private static func key(_ row: PRRow) -> String {
        "\(row.repo.id.uuidString)#\(row.pr.number)"
    }

    func phase(for row: PRRow) -> AIReviewPhase { phases[Self.key(row)] ?? .idle }

    /// Starts a review for `row` (no-op if one is already running for it). Fails
    /// fast when no eligible approver. Runs in a Task NOT tied to any view, so
    /// Back doesn't cancel it.
    func start(row: PRRow) {
        let key = Self.key(row)
        guard !running.contains(key) else { return }
        running.insert(key)

        Task {
            defer { self.running.remove(key) }

            guard let approver = await self.resolveApprover(row) else {
                self.phases[key] = .failed("無合格的 approver(你不能 approve 自己的 PR,也沒有其他帳號可用),無法使用 AI Review。")
                return
            }
            self.phases[key] = .running([])

            let files: [PRFileChange]
            do { files = try await self.loadFiles(row) }
            catch { self.phases[key] = .failed("無法取得 PR 變更:\(error.localizedDescription)"); return }
            let diff = ClaudeReviewPrompt.diffText(files: files)

            let onLine: @Sendable (String) -> Void = { line in
                Task { @MainActor [weak self] in self?.appendLine(line, to: key) }
            }

            switch await self.runReview(row, diff, onLine) {
            case .failed(let m):
                self.phases[key] = .failed(m)
            case .success(let review):
                switch review.verdict {
                case .approve:
                    if let err = await self.approve(row, approver, Self.reviewBody(from: review)) {
                        self.phases[key] = .failed("Approve 失敗:\(err)")
                    } else {
                        self.phases[key] = .done(review, actedAs: approver.login)
                    }
                case .issuesFound:
                    if let err = await self.comment(row, approver, Self.reviewBody(from: review)) {
                        self.phases[key] = .failed("發 comment 失敗:\(err)")
                    } else {
                        self.phases[key] = .done(review, actedAs: approver.login)
                    }
                }
            }
        }
    }

    private func appendLine(_ line: String, to key: String) {
        guard case .running(var lines) = (phases[key] ?? .idle) else { return }
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        phases[key] = .running(lines)
    }

    /// Formats a review into a tidy markdown body for the GitHub PR comment /
    /// approval review. Header reflects the verdict; Claude's `summary` (already
    /// markdown bullets) is the body; concrete issues get their own section; a
    /// footer attributes the review.
    static func reviewBody(from review: ClaudeReview) -> String {
        let header = review.verdict == .approve
            ? "## ✅ AI Review · Approved"
            : "## ⚠️ AI Review · 發現需處理的問題"
        var parts = [header, "", review.summary]
        if !review.issues.isEmpty {
            parts.append("")
            parts.append("### 需處理的問題")
            parts.append(contentsOf: review.issues.map { "- \($0)" })
        }
        parts.append("")
        parts.append("---")
        parts.append("*Reviewed by Claude Code*")
        return parts.joined(separator: "\n")
    }
}
