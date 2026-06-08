import XCTest
import GRDB
import Observation
@testable import Aerie

/// Regression test for the "refresh button crashes" bug (approve a PR → it gets
/// auto-merged → return to the list → press Refresh → crash).
///
/// Root cause: `PRsViewModel` was `@Observable` but NOT `@MainActor`, so its
/// `nonisolated async refresh()` ran on the cooperative pool and mutated
/// `self.state` OFF the main actor. The app fires one `Task { await
/// prsVM.refresh() }` per `.aeriePRCacheDidChange` (one per repo per tick), so
/// several of those off-main writes raced each other and SwiftUI's main-thread
/// reads — reliably fatal when a merged PR's row was being torn down.
///
/// The fix isolates the VM to `@MainActor`. This test pins the invariant: the
/// `state` mutation must land on the main thread. It fails on the un-isolated
/// VM and passes once `@MainActor` serialises the write onto main.
@MainActor
final class PRsViewModelConcurrencyTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDown() {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs.removeAll()
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    private func seedRepoWithPR(_ db: AppDatabase) async throws {
        let acctId = UUID()
        try await db.dbQueue.write { c in
            try c.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [acctId.uuidString, "tester", "github.com"]
            )
        }
        let repo = Repository(
            id: UUID(),
            name: "Repo",
            localPath: URL(fileURLWithPath: "/tmp/Repo"),
            githubOwner: "octocat",
            githubRepo: "repo",
            defaultBranch: "main",
            primaryAccountId: acctId,
            sortOrder: 0,
            hidden: false
        )
        try await db.repos.insert(repo)
        let pr = PullRequest(
            id: UUID(),
            repoId: repo.id,
            number: 1,
            title: "PR",
            authorLogin: "carlos-li",
            sourceBranch: "feat/x",
            isMine: true,
            state: .open,
            ciState: .success,
            reviewState: .approved,
            labels: [],
            htmlUrl: URL(string: "https://github.com/octocat/repo/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await db.prCache.upsert([pr], for: repo.id)
    }

    func test_refresh_mutatesStateOnMainThread() async throws {
        let db = try makeDB()
        try await seedRepoWithPR(db)
        let vm = PRsViewModel(db: db)

        // `withObservationTracking`'s `onChange` runs synchronously, on the
        // thread performing the mutation, right before `state` changes — so it
        // captures exactly where the write lands.
        let mutationThreadWasMain = ThreadFlag()
        withObservationTracking {
            _ = vm.state
        } onChange: {
            mutationThreadWasMain.value = Thread.isMainThread
        }

        await vm.refresh()

        guard case .ready = vm.state else {
            return XCTFail("Expected .ready, got \(vm.state)")
        }
        XCTAssertTrue(
            mutationThreadWasMain.value,
            "refresh() mutated `state` off the main thread — the data race that crashes the refresh button."
        )
    }
}

/// Tiny reference box so the `@Sendable` `onChange` closure can hand a value back
/// across the (test-only) thread hop without capturing a `var` directly.
private final class ThreadFlag: @unchecked Sendable {
    var value = false
}
