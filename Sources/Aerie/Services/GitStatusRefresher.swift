import Foundation

/// Refreshes one repo's local git status into the cache: looks up the repo,
/// reads its live status via `GitService`, and upserts the result into
/// `gitStatusCache`. This is the per-repo unit the `PollingScheduler`'s refresh
/// closure invokes — extracted into its own `Sendable` type so the polling
/// integration is testable without spinning up the live scheduler loop.
///
/// `Sendable` holds because `AppDatabase` is an actor and `GitService` is
/// actor-constrained (`protocol GitService: Actor`); `AppDatabase`'s DAO
/// accessors are `nonisolated`, so this runs entirely off the main actor.
struct GitStatusRefresher: Sendable {
    let db: AppDatabase
    let gitService: any GitService

    /// Find repo → `readStatus` → `upsert`. Best-effort: a moved, deleted, or
    /// otherwise non-git `localPath` (or an unknown id) just leaves the prior
    /// cached status in place rather than throwing — one bad repo must not kill
    /// the polling loop.
    func refresh(repoId: UUID) async {
        do {
            guard let repo = try await db.repos.find(id: repoId) else { return }
            let status = try await gitService.readStatus(
                at: repo.localPath, repoId: repoId
            )
            try await db.gitStatusCache.upsert(status)
        } catch {
            // Swallowed by design — see doc comment.
        }
    }
}
