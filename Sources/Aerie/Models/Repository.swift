import Foundation

struct Repository: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var localPath: URL
    var githubOwner: String
    var githubRepo: String
    var defaultBranch: String
    var primaryAccountId: UUID
    var sortOrder: Int
    var hidden: Bool
    /// When true, `PRSyncService`/`IssueSyncService`/`MergedBranchSync` skip
    /// this repo — no GitHub API calls — while local git operations (Open,
    /// Reset, Discard, worktrees) and the dashboard card keep working.
    /// Defaulted so existing call sites don't need updating.
    var apiSyncDisabled: Bool = false
}
