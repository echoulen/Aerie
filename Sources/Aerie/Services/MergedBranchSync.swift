import Foundation

/// The single GitHub-fetch capability `MergedBranchSync` needs. Narrow protocol
/// so tests can supply an in-memory fetcher without the full `MultiAccountAPI`
/// actor. `MultiAccountAPI` conforms below.
protocol MergedBranchFetching: Sendable {
    func mergedPR(
        owner: String,
        repo: String,
        headBranch: String,
        accountId: UUID
    ) async throws -> MultiAccountAPIResult<MergedPRRef?>
}

extension MultiAccountAPI: MergedBranchFetching {}

/// Detects whether a repo's checked-out branch has already been merged via a PR,
/// and maintains the `merged_branch_cache` accordingly. Runs per repo inside the
/// `PollingScheduler` closure, AFTER `GitStatusRefresher` (it reads the cached
/// `LocalGitStatus.currentBranch`).
///
/// Only off-default branches are queried — a repo on its default branch can't be
/// "merged away". On default (or missing status), the cache entry is cleared so
/// the pill drops once the user switches back. Errors are swallowed (logged): one
/// repo's failure must not abort a polling tick.
actor MergedBranchSync {
    private let db: AppDatabase
    private let api: MergedBranchFetching

    init(db: AppDatabase, api: MergedBranchFetching) {
        self.db = db
        self.api = api
    }

    /// Syncs a single repo. Safe to call from a polling tick — never throws.
    func sync(repoId: UUID) async {
        do {
            guard let repo = try await db.repos.find(id: repoId) else { return }
            guard !repo.apiSyncDisabled else { return }
            guard let status = try await db.gitStatusCache.status(forRepo: repoId),
                  status.currentBranch != repo.defaultBranch else {
                // On default branch (or no status yet) → nothing to detect.
                try await db.mergedBranchCache.clear(forRepo: repoId)
                return
            }
            let result = try await api.mergedPR(
                owner: repo.githubOwner,
                repo: repo.githubRepo,
                headBranch: status.currentBranch,
                accountId: repo.primaryAccountId
            )
            if let ref = result.value {
                try await db.mergedBranchCache.upsert(MergedBranchInfo(
                    repoId: repoId,
                    branch: status.currentBranch,
                    prNumber: ref.number,
                    prUrl: ref.url,
                    headOid: ref.headOid,
                    mergedAt: ref.mergedAt
                ))
            } else {
                try await db.mergedBranchCache.clear(forRepo: repoId)
            }
        } catch {
            // Swallow — one repo's failure shouldn't abort the tick.
            NSLog("MergedBranchSync: sync failed for repo \(repoId): \(error)")
        }
    }
}
