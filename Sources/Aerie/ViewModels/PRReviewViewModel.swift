import SwiftUI
import Observation

/// Loading / loaded / empty / error states for the code review screen, mirroring
/// `PRsState`'s shape.
enum PRReviewState: Equatable {
    case loading
    case ready([PRFileChange])
    case empty
    case error(String)
}

/// Drives the code review screen for a single PR. Unlike the list view models
/// (which read cached DB state), this fetches the PR's changed files on demand
/// and holds them in memory only — the diff is never persisted. Also resolves
/// which account may approve the PR (the author can't approve their own).
@Observable
final class PRReviewViewModel {
    let row: PRRow
    private(set) var state: PRReviewState = .loading
    /// Computed in `load()` once the account list is available.
    private(set) var resolution = ApproverResolution(eligible: [], defaultApprover: nil)

    private let loadFiles: (PRRow) async throws -> [PRFileChange]
    private let accountsProvider: () async -> [GitHubAccount]

    init(
        row: PRRow,
        loadFiles: @escaping (PRRow) async throws -> [PRFileChange],
        accountsProvider: @escaping () async -> [GitHubAccount]
    ) {
        self.row = row
        self.loadFiles = loadFiles
        self.accountsProvider = accountsProvider
    }

    /// Resolves the approver set, then fetches the PR's changed files. Safe to
    /// call again (e.g. a Retry button) — it resets to `.loading` first.
    func load() async {
        state = .loading
        let accounts = await accountsProvider()
        resolution = ApproverResolver.resolve(
            accounts: accounts,
            boundAccountId: row.repo.primaryAccountId,
            authorLogin: row.pr.authorLogin
        )
        do {
            let files = try await loadFiles(row)
            state = files.isEmpty ? .empty : .ready(files)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
