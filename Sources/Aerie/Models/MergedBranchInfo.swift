import Foundation

/// A repo's checked-out (off-default) branch that has already been merged via a
/// GitHub PR. Cached per repo (`repoId` is the cache key) and projected onto
/// `RepoRow.mergedBranch`, which drives the `merged · #N` pill and the
/// "Reset & delete branch" affordance on the repo card.
struct MergedBranchInfo: Codable, Equatable, Sendable {
    let repoId: UUID
    /// The merged branch — equals `LocalGitStatus.currentBranch` at detection time.
    let branch: String
    let prNumber: Int
    let prUrl: URL
    /// The merged PR's head SHA (GraphQL `headRefOid`). Stored as corroborating
    /// detail; not used to gate display or deletion in this version.
    let headOid: String
    let mergedAt: Date
}
