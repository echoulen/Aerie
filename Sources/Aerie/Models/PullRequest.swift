import Foundation

enum PRState: String, Codable, Equatable, CaseIterable {
    case open
    case closed
    case merged
}

enum CIState: String, Codable, Equatable, CaseIterable {
    case success
    case failure
    case pending
    case none
}

enum ReviewState: String, Codable, Equatable, CaseIterable {
    case approved
    case changesRequested
    case reviewRequired
}

struct PullRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let repoId: UUID
    let number: Int
    let title: String
    let authorLogin: String
    let sourceBranch: String
    let isMine: Bool
    let state: PRState
    let ciState: CIState
    let reviewState: ReviewState
    let labels: [String]
    let htmlUrl: URL
    let updatedAt: Date
    /// Login of the most recent approving reviewer, when the PR is approved.
    /// Optional + defaulted so existing call sites and older cached rows (which
    /// predate this field) keep decoding/constructing without change.
    var approvedBy: String? = nil
    /// Diff size from GitHub: lines added / removed and files changed. Optional
    /// + defaulted for the same back-compat reason as `approvedBy`.
    var additions: Int? = nil
    var deletions: Int? = nil
    var changedFiles: Int? = nil
    /// GitHub's authoritative merge-state (`mergeStateStatus`): CLEAN, UNSTABLE,
    /// BLOCKED, DIRTY, DRAFT, BEHIND, HAS_HOOKS, UNKNOWN. Drives whether the
    /// Merge button lights up. Optional + defaulted (older cached rows lack it).
    var mergeStateStatus: String? = nil
}

extension PullRequest {
    /// Single source of truth for "will a one-click squash merge go through?",
    /// shared by the Merge button (which reads a *cached* row) and the
    /// pre-merge re-validation in `MultiAccountAPI.mergePR` (which reads a
    /// *fresh* row). Returns nil when the PR is mergeable, otherwise a short,
    /// user-facing reason the merge dialog can surface.
    ///
    /// Mirrors what the GitHub web UI gates on: trust the authoritative
    /// `mergeStateStatus` when present, and fall back to CI + review only when
    /// it's absent (older cached rows / still computing). A *failing* CI rollup
    /// is an Aerie policy block on top — we won't offer a one-click merge over
    /// red CI even when GitHub technically would.
    var mergeBlockReason: String? {
        guard state == .open else { return "the pull request is \(state.rawValue)" }
        if ciState == .failure { return "CI is failing" }
        switch mergeStateStatus {
        case "CLEAN", "UNSTABLE", "HAS_HOOKS", "BEHIND":
            // GitHub will accept the merge (no branch-protection block, no
            // conflicts). UNSTABLE = non-required checks pending/failing.
            return nil
        case "DIRTY":
            return "the branch has merge conflicts"
        case "BLOCKED":
            return "branch protection is blocking it (e.g. a required review or status check)"
        case "DRAFT":
            return "it is still a draft"
        default:
            // UNKNOWN, or older cached rows that predate the field: be
            // permissive — approval is NOT required (many repos don't enforce
            // reviews); only a hard failure or an explicit "changes requested"
            // holds the merge back.
            if ciState == .pending { return "CI is still running" }
            if reviewState == .changesRequested { return "changes were requested" }
            return nil
        }
    }

    /// Whether GitHub will accept a one-click squash merge right now.
    var isMergeableByGitHub: Bool { mergeBlockReason == nil }
}
