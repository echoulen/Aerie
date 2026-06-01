import Foundation

/// The local checkout state of a specific PR's source branch — computed
/// per (Repository, PullRequest.head.ref) at fetch time, cached alongside
/// the PR. Lets the PRs view render combined GitHub + local status.
struct PRLocalState: Codable, Equatable {
    let prId: UUID
    let sourceBranch: String
    let localBranchExists: Bool
    let isCurrentBranch: Bool
    // Following are only meaningful when isCurrentBranch == true.
    // When the branch exists locally but isn't checked out, only existence is known.
    let dirty: Bool?
    let ahead: Int?
    let behind: Int?
    let unpushed: Int?
}
