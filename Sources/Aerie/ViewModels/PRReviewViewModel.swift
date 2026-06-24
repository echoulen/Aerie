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

/// Drives the diff view for one PR: fetches changed files on demand (never
/// persisted) and resolves which account may approve. AI-review execution/state
/// lives in `AIReviewStore` (held by the shell), not here, so it survives this
/// screen being rebuilt.
@MainActor
@Observable
final class PRReviewViewModel {
    let row: PRRow
    private(set) var state: PRReviewState = .loading
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
