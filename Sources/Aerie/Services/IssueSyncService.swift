import Foundation

/// The single GitHub-fetch capability `IssueSyncService` needs. Extracted as a
/// narrow protocol so tests can supply an in-memory fetcher without standing up
/// the full `MultiAccountAPI` actor. `MultiAccountAPI` conforms below.
protocol IssueFetching: Sendable {
    /// Fetches the repo's open issues using exactly `accountId`'s token.
    func listOpenIssues(
        owner: String,
        repo: String,
        repoId: UUID,
        accountId: UUID
    ) async throws -> MultiAccountAPIResult<[Issue]>
}

extension MultiAccountAPI: IssueFetching {}

/// The issue fetch → cache orchestration that sits between the
/// `PollingScheduler` and the persistence layer — the issue-side mirror of
/// ``PRSyncService``.
///
/// Given a repoId it loads the `Repository`, fetches its open issues with the
/// repo's **bound** account (`primaryAccountId`), writes them into
/// `issue_cache`, and fires `onChange` so the view layer can re-project.
///
/// Errors are deliberately swallowed (logged, not thrown): a single repo's
/// failure must not crash a polling tick or block the other repos in the same
/// tick. On failure the existing cache is left untouched and `onChange` does not
/// fire (nothing changed).
actor IssueSyncService {
    private let db: AppDatabase
    private let api: IssueFetching
    private let onChange: @Sendable () async -> Void

    init(
        db: AppDatabase,
        api: IssueFetching,
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
            let result = try await api.listOpenIssues(
                owner: repo.githubOwner,
                repo: repo.githubRepo,
                repoId: repo.id,
                accountId: repo.primaryAccountId
            )
            // "Assigned to you" spans every connected account, not just the one
            // that synced this repo. Resolve it here, where we can see them all.
            let myLogins = Set(
                ((try? await db.accounts.all()) ?? []).map { $0.login.lowercased() }
            )
            let issues = result.value.map { $0.resolvingAssignedToMe(myLogins: myLogins) }
            try await db.issueCache.upsert(issues, for: repo.id)
            await onChange()
        } catch {
            // Swallow — one repo's failure shouldn't abort the tick. The stale
            // cache (if any) stays put; the next tick retries.
            NSLog("IssueSyncService: sync failed for repo \(repoId): \(error)")
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
