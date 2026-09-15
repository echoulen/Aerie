import Foundation

/// Refreshes one repo's local git status into the cache: looks up the repo,
/// reads its live status via `GitService`, and upserts the result into
/// `gitStatusCache`. This is the per-repo unit the `PollingScheduler`'s refresh
/// closure invokes — extracted into its own `Sendable` type so the polling
/// integration is testable without spinning up the live scheduler loop.
///
/// The read itself is gated (see `WorkingTreeWatcher.swift`): a tree that
/// hasn't changed since the last read is skipped, and a repo whose last read
/// was slow is only re-read on the long interval. The cache keeps its previous
/// reading either way.
///
/// `Sendable` holds because `AppDatabase` is an actor and `GitService` is
/// actor-constrained (`protocol GitService: Actor`); `AppDatabase`'s DAO
/// accessors are `nonisolated`, so this runs entirely off the main actor.
struct GitStatusRefresher: Sendable {
    let db: AppDatabase
    let gitService: any GitService
    let changes: any WorkingTreeChangeSource
    private let ledger = StatusReadLedger()
    private let now: @Sendable () -> Date

    init(
        db: AppDatabase,
        gitService: any GitService,
        changes: any WorkingTreeChangeSource = AlwaysChanged(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.db = db
        self.gitService = gitService
        self.changes = changes
        self.now = now
    }

    /// Find repo → gate → `readStatus` → `upsert`. Best-effort: a moved,
    /// deleted, or otherwise non-git `localPath` (or an unknown id) just leaves
    /// the prior cached status in place rather than throwing — one bad repo
    /// must not kill the polling loop.
    func refresh(repoId: UUID) async {
        do {
            guard let repo = try await db.repos.find(id: repoId) else { return }

            // Backoff first, then consume: consuming while still backed off
            // would drop a change that should be picked up once the interval
            // ends. Consume *before* the read so a write that lands mid-read
            // re-arms the flag for the next tick.
            guard !StatusReadPolicy.isInSlowBackoff(ledger.record(for: repoId), now: now()) else { return }
            guard changes.consumeChange(at: repo.localPath) else { return }

            let started = ContinuousClock.now
            let status = try await gitService.readStatus(
                at: repo.localPath, repoId: repoId
            )
            let elapsed = started.duration(to: .now)
            ledger.set(StatusReadRecord(
                at: now(),
                duration: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            ), for: repoId)
            try await db.gitStatusCache.upsert(status)
        } catch {
            // Swallowed by design — see doc comment.
        }
    }
}
