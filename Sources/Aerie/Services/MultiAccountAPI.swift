import Foundation

/// Result of a `MultiAccountAPI` call. Reports both the value and which account
/// (token) successfully fulfilled the request, so callers can attribute
/// rate-limit consumption and surface "made the call as <user>" in the UI.
struct MultiAccountAPIResult<T: Sendable>: Sendable {
    let value: T
    let successfulAccountId: UUID
}

/// Surface of `MultiAccountAPI` needed by view models that just want to read
/// the per-account "last call" timestamp. Extracted so tests can supply a
/// stub without standing up the full actor.
protocol AccountUsageTracker: Sendable {
    func lastUsed(forAccount accountId: UUID) async -> Date?
}

/// Wraps a `GitHubAPIClient` and tries the configured accounts in order. On
/// auth failures (401/403) it falls back to the next account; on network
/// errors (no HTTP status) it propagates immediately — cycling through
/// accounts won't help if the network is down.
///
/// The account list + token map are passed as closures rather than snapshots
/// so the underlying `AuthService` can mutate its state without invalidating
/// this wrapper.
actor MultiAccountAPI {
    let client: GitHubAPIClient
    let tokensByAccount: @Sendable () async -> [UUID: String]
    let accountsInOrder: @Sendable () async -> [UUID]

    /// Records the `Date()` of the most recent successful call routed
    /// through each account. Populated inside `tryAcrossAccounts`.
    private var lastUsedByAccount: [UUID: Date] = [:]

    /// Allows tests to inject a deterministic clock. Production omits this
    /// argument and gets the wall clock.
    private let now: @Sendable () -> Date

    init(
        client: GitHubAPIClient,
        tokensByAccount: @escaping @Sendable () async -> [UUID: String],
        accountsInOrder: @escaping @Sendable () async -> [UUID],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.tokensByAccount = tokensByAccount
        self.accountsInOrder = accountsInOrder
        self.now = now
    }

    func listOpenPRs(
        owner: String,
        repo: String,
        repoId: UUID
    ) async throws -> MultiAccountAPIResult<[PullRequest]> {
        try await tryAcrossAccounts { token in
            try await self.client.listOpenPRs(
                owner: owner,
                repo: repo,
                repoId: repoId,
                token: token
            )
        }
    }

    func mergePR(
        owner: String,
        repo: String,
        number: Int,
        method: MergeMethod
    ) async throws -> MultiAccountAPIResult<MergeResult> {
        try await tryAcrossAccounts { token in
            try await self.client.mergePR(
                owner: owner,
                repo: repo,
                number: number,
                method: method,
                token: token
            )
        }
    }

    /// Snapshot of the last response's rate-limit headers for the given
    /// account, or nil if we have no record (account unknown, or no call
    /// made yet on its token).
    func rateLimit(forAccount accountId: UUID) async -> RateLimitSnapshot? {
        let tokens = await tokensByAccount()
        guard let token = tokens[accountId] else { return nil }
        return client.lastRateLimit(token: token)
    }

    /// Timestamp of the most recent successful call routed through `accountId`,
    /// or nil if no call has succeeded against that account yet. Updated as a
    /// side effect of `tryAcrossAccounts` on the success branch.
    func lastUsed(forAccount accountId: UUID) async -> Date? {
        lastUsedByAccount[accountId]
    }

    // MARK: Fallback loop

    private func tryAcrossAccounts<T: Sendable>(
        _ op: @Sendable (String) async throws -> T
    ) async throws -> MultiAccountAPIResult<T> {
        let order = await accountsInOrder()
        let tokens = await tokensByAccount()

        var lastError: Error?
        for accountId in order {
            guard let token = tokens[accountId] else { continue }
            do {
                let value = try await op(token)
                lastUsedByAccount[accountId] = now()
                return MultiAccountAPIResult(value: value, successfulAccountId: accountId)
            } catch let err as GitHubAPIError where err.status == 401 || err.status == 403 {
                // Auth failure — fall through to the next account.
                lastError = err
                continue
            } catch {
                // Non-auth error (network, decode, etc.) — propagate immediately.
                throw error
            }
        }

        // Ran out of accounts. Surface the most recent failure, or a synthetic
        // error if no account was even tried.
        if let lastError {
            throw lastError
        }
        throw GitHubAPIError(status: 0, message: "no accounts configured")
    }
}

extension MultiAccountAPI: AccountUsageTracker {}
