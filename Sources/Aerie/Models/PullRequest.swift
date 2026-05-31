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
