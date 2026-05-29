import Foundation
import Observation

/// View model for the Settings → Repositories screen.
///
/// Separate from the main-window `ReposViewModel` because this surface
/// edits the repo set (reorder / remove / change account) rather than
/// projecting cached git status. We deliberately expose the raw
/// `Repository` list — the Settings row doesn't need the cached status.
@Observable
final class RepositoriesViewModel {
    private(set) var repos: [Repository] = []
    private(set) var accounts: [GitHubAccount] = []
    private(set) var error: String?

    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// Re-reads repos + accounts from the database. `repos` arrives
    /// already ordered by `(sort_order, name)` from `RepoDAO.all()`.
    func refresh() async {
        do {
            repos = try await db.repos.all()
            accounts = try await db.accounts.all()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Persists a freshly-detected repo, then refreshes so it appears in
    /// the list and the sidebar count.
    ///
    /// `DetectedRepo.suggestedAccountId` is the account matched on host —
    /// it's nil when nothing matched. The `repos.account_id` column is
    /// `NOT NULL REFERENCES accounts(id)`, so we fall back to the first
    /// known account; the user can reassign via the row's account dropdown.
    /// With no accounts at all there's nothing valid to satisfy the FK, so
    /// we surface an error and write nothing.
    ///
    /// Returns whether the repo was persisted.
    @discardableResult
    func add(_ detected: DetectedRepo) async -> Bool {
        if accounts.isEmpty {
            accounts = (try? await db.accounts.all()) ?? []
        }
        guard let accountId = detected.suggestedAccountId ?? accounts.first?.id else {
            error = "Add a GitHub account before adding a repository."
            return false
        }
        let nextOrder = (repos.map(\.sortOrder).max() ?? -1) + 1
        let repo = Repository(
            id: UUID(),
            name: detected.url.lastPathComponent,
            localPath: detected.url,
            githubOwner: detected.githubOwner,
            githubRepo: detected.githubRepo,
            defaultBranch: detected.defaultBranch,
            primaryAccountId: accountId,
            sortOrder: nextOrder,
            hidden: false
        )
        do {
            try await db.repos.insert(repo)
            await refresh()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Move the row at index `from` to position `to` (in the
    /// pre-removal coordinate space used by SwiftUI's `move(fromOffsets:toOffset:)`).
    /// Updates `sort_order` for ALL rows so the persisted order matches
    /// the new visual order.
    func reorder(from: Int, to: Int) async {
        guard from != to, from < repos.count, to <= repos.count else { return }
        var reordered = repos
        let moved = reordered.remove(at: from)
        let dest = to > from ? to - 1 : to
        reordered.insert(moved, at: dest)
        for (i, r) in reordered.enumerated() {
            try? await db.repos.setSortOrder(id: r.id, i)
        }
        repos = reordered
    }

    /// Deletes the repo from the DB and refreshes.
    func remove(id: UUID) async {
        try? await db.repos.delete(id: id)
        await refresh()
    }

    /// Re-assigns the repo's primary account.
    ///
    /// Returns `false` (without mutating anything) if the supplied
    /// `accountId` isn't in the currently loaded `accounts` list — the
    /// UI dropdown should never offer an unknown id, but we guard
    /// against drift just in case.
    @discardableResult
    func setAccount(repoId: UUID, accountId: UUID) async -> Bool {
        guard accounts.contains(where: { $0.id == accountId }) else { return false }
        try? await db.repos.setAccount(id: repoId, accountId)
        await refresh()
        return true
    }
}
