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

/// Owns AI-review execution + state for ALL PRs, keyed by PR id, so a review
/// survives the review screen being torn down and rebuilt (Back → re-enter).
/// Held by `MainShell`, not the per-screen view model.
@MainActor
@Observable
final class AIReviewStore {
    private(set) var phases: [UUID: AIReviewPhase] = [:]
    private var running: Set<UUID> = []
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

    func phase(for id: UUID) -> AIReviewPhase { phases[id] ?? .idle }

    /// Starts a review for `row` (no-op if one is already running for it). Fails
    /// fast when no eligible approver. Runs in a Task NOT tied to any view, so
    /// Back doesn't cancel it.
    func start(row: PRRow) {
        let id = row.pr.id
        guard !running.contains(id) else { return }
        running.insert(id)

        Task {
            defer { self.running.remove(id) }

            guard let approver = await self.resolveApprover(row) else {
                self.phases[id] = .failed("無合格的 approver(你不能 approve 自己的 PR,也沒有其他帳號可用),無法使用 AI Review。")
                return
            }
            self.phases[id] = .running([])

            let files: [PRFileChange]
            do { files = try await self.loadFiles(row) }
            catch { self.phases[id] = .failed("無法取得 PR 變更:\(error.localizedDescription)"); return }
            let diff = ClaudeReviewPrompt.diffText(files: files)

            let onLine: @Sendable (String) -> Void = { line in
                Task { @MainActor [weak self] in self?.appendLine(line, to: id) }
            }

            switch await self.runReview(row, diff, onLine) {
            case .failed(let m):
                self.phases[id] = .failed(m)
            case .success(let review):
                switch review.verdict {
                case .approve:
                    if let err = await self.approve(row, approver, review.summary) {
                        self.phases[id] = .failed("Approve 失敗:\(err)")
                    } else {
                        self.phases[id] = .done(review, actedAs: approver.login)
                    }
                case .issuesFound:
                    if let err = await self.comment(row, approver, Self.commentBody(from: review)) {
                        self.phases[id] = .failed("發 comment 失敗:\(err)")
                    } else {
                        self.phases[id] = .done(review, actedAs: approver.login)
                    }
                }
            }
        }
    }

    private func appendLine(_ line: String, to id: UUID) {
        guard case .running(var lines) = phase(for: id) else { return }
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        phases[id] = .running(lines)
    }

    /// Formats Claude's issues into a PR comment body.
    static func commentBody(from review: ClaudeReview) -> String {
        var lines = ["**AI Review — 發現需處理的問題**", "", review.summary]
        if !review.issues.isEmpty {
            lines.append("")
            lines.append(contentsOf: review.issues.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}
