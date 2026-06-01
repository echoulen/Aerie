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
    /// Account binding precedence: an explicit `accountId` (the add-repo
    /// sheet's resolved/user-picked choice) wins; otherwise the detector's
    /// `suggestedAccountId` (host/login match); otherwise the first known
    /// account. The `repos.account_id` column is `NOT NULL REFERENCES
    /// accounts(id)`, so with no accounts at all there's nothing valid to
    /// satisfy the FK — we surface an error and write nothing.
    ///
    /// Returns whether the repo was persisted.
    @discardableResult
    func add(_ detected: DetectedRepo, accountId: UUID? = nil) async -> Bool {
        if accounts.isEmpty {
            accounts = (try? await db.accounts.all()) ?? []
        }
        guard let accountId = accountId ?? detected.suggestedAccountId ?? accounts.first?.id else {
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
            await Self.postReposDidChange()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Notifies the rest of the app (notably the main window's Repos tab) that
    /// the tracked repo set changed, so it can re-project without waiting for a
    /// polling tick. Posted on the main actor — `PassthroughSubject`/SwiftUI
    /// observers expect main-thread delivery.
    private static func postReposDidChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .aerieReposDidChange, object: nil)
        }
    }

    /// The repo list after moving the row at index `from` to position `to`
    /// (in the pre-removal coordinate space used by SwiftUI's
    /// `move(fromOffsets:toOffset:)`). Returns `nil` for a no-op / out-of-range
    /// move so callers can bail without touching the DB.
    private func movedOrder(from: Int, to: Int) -> [Repository]? {
        guard from != to, from < repos.count, to <= repos.count else { return nil }
        var reordered = repos
        let moved = reordered.remove(at: from)
        let dest = to > from ? to - 1 : to
        reordered.insert(moved, at: dest)
        return reordered
    }

    /// Persists `sort_order` for `reordered` so the stored order matches the
    /// new visual order. Each row is rewritten to its array index.
    private func persistOrder(_ reordered: [Repository]) async {
        for (i, r) in reordered.enumerated() {
            try? await db.repos.setSortOrder(id: r.id, i)
        }
    }

    /// Move the row at index `from` to position `to`. Updates `sort_order`
    /// for ALL rows so the persisted order matches the new visual order.
    func reorder(from: Int, to: Int) async {
        guard let reordered = movedOrder(from: from, to: to) else { return }
        repos = reordered
        await persistOrder(reordered)
    }

    /// Optimistic, synchronous reorder for drag-and-drop: settles the
    /// in-memory order in the SAME frame the user releases the grip (so the
    /// row doesn't flash back to its old slot), then persists `sort_order`
    /// in the background. Mirrors `reorder(from:to:)`'s move semantics.
    func applyReorder(from: Int, to: Int) {
        guard let reordered = movedOrder(from: from, to: to) else { return }
        repos = reordered
        Task { [reordered] in await persistOrder(reordered) }
    }

    /// Deletes the repo from the DB and refreshes.
    func remove(id: UUID) async {
        try? await db.repos.delete(id: id)
        await refresh()
        await Self.postReposDidChange()
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
