import Foundation

/// The single GitHub-fetch capability `PRSyncService` needs. Extracted as a
/// narrow protocol so tests can supply an in-memory fetcher without standing up
/// the full `MultiAccountAPI` actor. `MultiAccountAPI` conforms below.
protocol PRFetching: Sendable {
    /// Fetches the repo's open PRs using exactly `accountId`'s token.
    func listOpenPRs(
        owner: String,
        repo: String,
        repoId: UUID,
        accountId: UUID
    ) async throws -> MultiAccountAPIResult<[PullRequest]>
}

extension MultiAccountAPI: PRFetching {}

/// The PR fetch → cache orchestration that sits between the `PollingScheduler`
/// and the persistence layer — the piece that was previously a no-op stub, so
/// the PRs tab always showed 0 (see issue #29).
///
/// Given a repoId it loads the `Repository`, fetches its open PRs with the
/// repo's **bound** account (`primaryAccountId`) — precise, one API call, and it
/// sidesteps the cross-account fallback path — writes them into `pr_cache`, and
/// fires `onChange` so the view layer can re-project.
///
/// Errors are deliberately swallowed (logged, not thrown): a single repo's
/// failure must not crash a polling tick or block the other repos in the same
/// tick. On failure the existing cache is left untouched and `onChange` does not
/// fire (nothing changed).
actor PRSyncService {
    private let db: AppDatabase
    private let api: PRFetching
    private let onChange: @Sendable () async -> Void

    init(
        db: AppDatabase,
        api: PRFetching,
        onChange: @escaping @Sendable () async -> Void = {}
    ) {
        self.db = db
        self.api = api
        self.onChange = onChange
    }

    /// Syncs a single repo. Safe to call from a polling tick — never throws.
    func sync(repoId: UUID) async {
        do {
            guard let repo = try await db.repos.find(id: repoId) else { return }
            let result = try await api.listOpenPRs(
                owner: repo.githubOwner,
                repo: repo.githubRepo,
                repoId: repo.id,
                accountId: repo.primaryAccountId
            )
            try await db.prCache.upsert(result.value, for: repo.id)
            await onChange()
        } catch {
            // Swallow — one repo's failure shouldn't abort the tick. The stale
            // cache (if any) stays put; the next tick retries.
            NSLog("PRSyncService: sync failed for repo \(repoId): \(error)")
        }
    }

    /// Syncs every non-hidden repo, in order. Used for the initial fetch on
    /// launch; the scheduler drives subsequent per-repo ticks.
    func syncAll() async {
        let repos = (try? await db.repos.all()) ?? []
        for repo in repos where !repo.hidden {
            await sync(repoId: repo.id)
        }
    }
}
