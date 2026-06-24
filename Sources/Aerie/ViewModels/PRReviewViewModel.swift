import SwiftUI
import Observation

/// Loading / loaded / empty / error states for the code review screen, mirroring
/// `PRsState`'s shape.
enum PRReviewState: Equatable {
    case loading
    case ready([PRFileChange])
    case empty
    case error(String)
}

/// AI-review lifecycle for the review screen, independent of the diff's
/// `PRReviewState`.
enum AIReviewPhase: Equatable {
    case idle
    case running
    case done(ClaudeReview)
    case failed(String)
}

/// Drives the code review screen for a single PR. Unlike the list view models
/// (which read cached DB state), this fetches the PR's changed files on demand
/// and holds them in memory only — the diff is never persisted. Also resolves
/// which account may approve the PR (the author can't approve their own).
///
/// `@MainActor` for the same reason the list view models are (see #67): `load()`
/// `await`s a network fetch, and a non-isolated async method can resume on a
/// background thread — mutating the `@Observable` `state`/`resolution` off the
/// main thread while SwiftUI reads them on it, a data race that can crash the
/// app on open. Main-actor isolation pins every mutation to the main thread.
@MainActor
@Observable
final class PRReviewViewModel {
    let row: PRRow
    private(set) var state: PRReviewState = .loading
    /// Computed in `load()` once the account list is available.
    private(set) var resolution = ApproverResolution(eligible: [], defaultApprover: nil)
    private(set) var aiReview: AIReviewPhase = .idle

    private let loadFiles: (PRRow) async throws -> [PRFileChange]
    private let accountsProvider: () async -> [GitHubAccount]
    private let runReview: (PRRow, String) async -> ClaudeReviewOutcome
    private let submitApprove: (PRRow, String) async -> String?   // returns error message, nil on success
    private let submitComment: (PRRow, String) async -> String?

    init(
        row: PRRow,
        loadFiles: @escaping (PRRow) async throws -> [PRFileChange],
        accountsProvider: @escaping () async -> [GitHubAccount],
        runReview: @escaping (PRRow, String) async -> ClaudeReviewOutcome
            = { _, _ in .failed("AI Review 尚未設定。") },
        submitApprove: @escaping (PRRow, String) async -> String? = { _, _ in nil },
        submitComment: @escaping (PRRow, String) async -> String? = { _, _ in nil }
    ) {
        self.row = row
        self.loadFiles = loadFiles
        self.accountsProvider = accountsProvider
        self.runReview = runReview
        self.submitApprove = submitApprove
        self.submitComment = submitComment
    }

    /// Resolves the approver set, then fetches the PR's changed files. Safe to
    /// call again (e.g. a Retry button) — it resets to `.loading` first.
    func load() async {
        state = .loading
        let accounts = await accountsProvider()
        resolution = ApproverResolver.resolve(
            accounts: accounts,
            boundAccountId: row.repo.primaryAccountId,
            authorLogin: row.pr.authorLogin
        )
        do {
            let files = try await loadFiles(row)
            state = files.isEmpty ? .empty : .ready(files)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Runs an AI review of this PR via the injected `runReview`, then acts on the
    /// verdict: approve (no major problems) submits an approving review carrying
    /// Claude's summary; issues_found posts a comment instead and never approves.
    /// Requires an eligible approver up front — without one this feature can't meet
    /// its purpose, so it fails fast rather than running Claude for nothing.
    func runAIReview() async {
        guard aiReview != .running else { return }   // ignore re-entry while a review is in flight
        guard resolution.canApprove else {
            aiReview = .failed("無合格的 approver(你不能 approve 自己的 PR,也沒有其他帳號可用),無法使用 AI Review。")
            return
        }
        aiReview = .running

        // Build the diff text from the already-loaded files; fetch if needed.
        let files: [PRFileChange]
        switch state {
        case .ready(let f): files = f
        case .empty: files = []
        default:
            do { files = try await loadFiles(row) }
            catch { aiReview = .failed("無法取得 PR 變更:\(error.localizedDescription)"); return }
        }
        let diff = ClaudeReviewPrompt.diffText(files: files)

        switch await runReview(row, diff) {
        case .failed(let msg):
            aiReview = .failed(msg)
        case .success(let review):
            switch review.verdict {
            case .approve:
                if let err = await submitApprove(row, review.summary) {
                    aiReview = .failed("Approve 失敗:\(err)")
                } else {
                    aiReview = .done(review)
                }
            case .issuesFound:
                let body = Self.commentBody(from: review)
                if let err = await submitComment(row, body) {
                    aiReview = .failed("發 comment 失敗:\(err)")
                } else {
                    aiReview = .done(review)
                }
            }
        }
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
