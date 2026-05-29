import Foundation
import Observation

/// One row in the Settings → Accounts list. Bundles the persisted
/// `GitHubAccount` with the ephemeral, runtime-derived fields the card
/// needs to render (scopes from `gh auth status`, primary flag from the
/// auth order, repo count from the DAO, last-used timestamp from
/// `MultiAccountAPI`).
struct AccountRow: Equatable, Identifiable {
    var id: UUID { account.id }
    let account: GitHubAccount
    /// OAuth scopes attached to this account's token, as reported by
    /// `gh auth status`. Empty if unknown.
    let scopes: [String]
    /// `true` when this is the first account in the auth bootstrap order —
    /// surfaces the "primary" pill in the UI.
    let isPrimary: Bool
    /// Number of `Repository` rows whose `primaryAccountId` points at this
    /// account.
    let repoCount: Int
    /// Wall-clock time of the most recent successful API call routed
    /// through this account, or nil if none yet.
    let lastUsed: Date?
}

/// View model for the Settings → Accounts screen.
///
/// The "where do scopes/primary come from?" question is deferred via
/// closures so the integration layer (Phase 16) can wire them through
/// from `AuthService` without this VM growing a hard dependency on it.
/// Same trick `ReposViewModel` uses with the DB — the VM stays narrow.
@Observable
final class AccountsViewModel {
    private(set) var rows: [AccountRow] = []
    private(set) var error: String? = nil
    /// Raw `gh --version` first line, surfaced by `AccountsScreen`'s banner.
    /// `nil` until the integration layer's provider returns something.
    private(set) var ghVersion: String? = nil

    private let db: AppDatabase
    private let api: any AccountUsageTracker
    private let scopesByAccount: () async -> [UUID: [String]]
    private let primaryAccountId: () async -> UUID?
    private let ghVersionProvider: () async -> String?

    init(
        db: AppDatabase,
        api: any AccountUsageTracker,
        scopesByAccount: @escaping () async -> [UUID: [String]],
        primaryAccountId: @escaping () async -> UUID?,
        ghVersion: @escaping () async -> String? = { nil }
    ) {
        self.db = db
        self.api = api
        self.scopesByAccount = scopesByAccount
        self.primaryAccountId = primaryAccountId
        self.ghVersionProvider = ghVersion
    }

    /// Re-reads accounts + repo counts + scopes + last-used and projects
    /// them into `rows`. On any throw, populates `error` and leaves the
    /// previous `rows` in place so the UI doesn't blank out on a transient
    /// failure.
    func refresh() async {
        do {
            let accounts = try await db.accounts.all()
            let allRepos = try await db.repos.all()
            let scopes = await scopesByAccount()
            let primary = await primaryAccountId()
            self.ghVersion = await ghVersionProvider()
            var built: [AccountRow] = []
            for acc in accounts {
                let count = allRepos.filter { $0.primaryAccountId == acc.id }.count
                let last = await api.lastUsed(forAccount: acc.id)
                built.append(AccountRow(
                    account: acc,
                    scopes: scopes[acc.id] ?? [],
                    isPrimary: primary == acc.id,
                    repoCount: count,
                    lastUsed: last
                ))
            }
            self.rows = built
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
