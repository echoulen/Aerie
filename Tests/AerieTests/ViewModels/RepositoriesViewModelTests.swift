import XCTest
import GRDB
@testable import Aerie

final class RepositoriesViewModelTests: XCTestCase {
    // MARK: - Helpers

    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    @discardableResult
    private func insertAccount(
        _ db: AppDatabase,
        id: UUID = UUID(),
        login: String = "tester",
        host: String = "github.com"
    ) throws -> UUID {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [id.uuidString, login, host]
            )
        }
        return id
    }

    private func detected(
        path: String = "/tmp/Example",
        owner: String = "octocat",
        repo: String = "hello-world",
        host: String = "github.com",
        suggestedAccountId: UUID? = nil
    ) -> DetectedRepo {
        DetectedRepo(
            url: URL(fileURLWithPath: path),
            githubOwner: owner,
            githubRepo: repo,
            host: host,
            defaultBranch: "main",
            currentBranch: "main",
            isDirty: false,
            suggestedAccountId: suggestedAccountId
        )
    }

    @discardableResult
    private func insertRepo(
        _ db: AppDatabase,
        accountId: UUID,
        name: String = "Example",
        owner: String = "octocat",
        repo: String = "hello-world",
        sortOrder: Int = 0,
        hidden: Bool = false
    ) async throws -> Repository {
        let r = Repository(
            id: UUID(),
            name: name,
            localPath: URL(fileURLWithPath: "/tmp/\(name)"),
            githubOwner: owner,
            githubRepo: repo,
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: sortOrder,
            hidden: hidden
        )
        try await db.repos.insert(r)
        return r
    }

    // MARK: - Tests

    func test_refresh_loadsReposSortedBySortOrder() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)

        let two = try await insertRepo(db, accountId: acct, name: "Charlie", repo: "charlie", sortOrder: 2)
        let zero = try await insertRepo(db, accountId: acct, name: "Alpha", repo: "alpha", sortOrder: 0)
        let one = try await insertRepo(db, accountId: acct, name: "Bravo", repo: "bravo", sortOrder: 1)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        XCTAssertEqual(vm.repos.count, 3)
        XCTAssertEqual(vm.repos.map { $0.id }, [zero.id, one.id, two.id])
        XCTAssertNil(vm.error)
    }

    func test_reorder_persistsNewOrder() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let a = try await insertRepo(db, accountId: acct, name: "Alpha", repo: "alpha", sortOrder: 0)
        let b = try await insertRepo(db, accountId: acct, name: "Bravo", repo: "bravo", sortOrder: 1)
        let c = try await insertRepo(db, accountId: acct, name: "Charlie", repo: "charlie", sortOrder: 2)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        // Move index 0 (a) to position 3 (end). SwiftUI move semantics:
        // from=0, to=3 means "insert after the last element".
        await vm.reorder(from: 0, to: 3)

        // Verify in-memory order.
        XCTAssertEqual(vm.repos.map { $0.id }, [b.id, c.id, a.id])

        // Verify persisted order.
        await vm.refresh()
        XCTAssertEqual(vm.repos.map { $0.id }, [b.id, c.id, a.id])

        // Verify sort_order is 0,1,2 for the new order.
        let foundB = try await db.repos.find(id: b.id)
        let foundC = try await db.repos.find(id: c.id)
        let foundA = try await db.repos.find(id: a.id)
        XCTAssertEqual(foundB?.sortOrder, 0)
        XCTAssertEqual(foundC?.sortOrder, 1)
        XCTAssertEqual(foundA?.sortOrder, 2)
    }

    func test_remove_deletesFromDB() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let a = try await insertRepo(db, accountId: acct, name: "Alpha", repo: "alpha", sortOrder: 0)
        let b = try await insertRepo(db, accountId: acct, name: "Bravo", repo: "bravo", sortOrder: 1)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()
        XCTAssertEqual(vm.repos.count, 2)

        await vm.remove(id: a.id)

        XCTAssertEqual(vm.repos.count, 1)
        XCTAssertEqual(vm.repos.first?.id, b.id)
        let found = try await db.repos.find(id: a.id)
        XCTAssertNil(found)
    }

    func test_remove_deletesRepoThatHasCachedRows() async throws {
        // Reproduces the reported "[x] does nothing" bug: once the sync
        // services have populated a repo's caches, deleting it tripped a
        // FOREIGN KEY constraint that `remove`'s `try?` silently swallowed,
        // leaving the row in place. The repo must vanish regardless.
        let db = try makeDB()
        let acct = try insertAccount(db)
        let a = try await insertRepo(db, accountId: acct, name: "Alpha", repo: "alpha", sortOrder: 0)
        let b = try await insertRepo(db, accountId: acct, name: "Bravo", repo: "bravo", sortOrder: 1)

        // Seed a cache row in each child table for the repo we'll remove.
        try await db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO pr_cache (repo_id, number, payload_json, fetched_at) VALUES (?, ?, ?, ?)",
                arguments: [a.id.uuidString, 1, "{}", 0.0]
            )
            try dbConn.execute(
                sql: "INSERT INTO git_status_cache (repo_id, payload_json, fetched_at) VALUES (?, ?, ?)",
                arguments: [a.id.uuidString, "{}", 0.0]
            )
            try dbConn.execute(
                sql: "INSERT INTO issue_cache (repo_id, number, payload_json, fetched_at) VALUES (?, ?, ?, ?)",
                arguments: [a.id.uuidString, 1, "{}", 0.0]
            )
        }

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()
        XCTAssertEqual(vm.repos.count, 2)

        await vm.remove(id: a.id)

        XCTAssertEqual(vm.repos.count, 1)
        XCTAssertEqual(vm.repos.first?.id, b.id)
        let found = try await db.repos.find(id: a.id)
        XCTAssertNil(found)
    }

    func test_setAccount_validatesAccountExists() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r = try await insertRepo(db, accountId: acct)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let unknown = UUID()
        let result = await vm.setAccount(repoId: r.id, accountId: unknown)
        XCTAssertFalse(result)

        // Repo's account unchanged.
        let found = try await db.repos.find(id: r.id)
        XCTAssertEqual(found?.primaryAccountId, acct)
    }

    func test_add_persistsDetectedRepo_andRefreshes() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()
        XCTAssertEqual(vm.repos.count, 0)

        let ok = await vm.add(detected(path: "/tmp/ChaosOfThreeKingdoms", owner: "echoulen", repo: "ChaosOfThreeKingdoms"))
        XCTAssertTrue(ok)

        // Reflected in VM state...
        XCTAssertEqual(vm.repos.count, 1)
        XCTAssertEqual(vm.repos.first?.name, "ChaosOfThreeKingdoms")
        XCTAssertEqual(vm.repos.first?.githubOwner, "echoulen")
        XCTAssertEqual(vm.repos.first?.primaryAccountId, acct)
        XCTAssertNil(vm.error)

        // ...and actually persisted.
        let all = try await db.repos.all()
        XCTAssertEqual(all.count, 1)
    }

    func test_add_usesSuggestedAccount_whenPresent() async throws {
        let db = try makeDB()
        let other = try insertAccount(db, login: "aaa-first")   // sorts first
        let suggested = try insertAccount(db, login: "zzz-suggested")

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let ok = await vm.add(detected(suggestedAccountId: suggested))
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.repos.first?.primaryAccountId, suggested)
        XCTAssertNotEqual(vm.repos.first?.primaryAccountId, other)
    }

    func test_add_fallsBackToFirstAccount_whenNoSuggestion() async throws {
        let db = try makeDB()
        let first = try insertAccount(db, login: "aaa-first")
        _ = try insertAccount(db, login: "zzz-second")

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let ok = await vm.add(detected(suggestedAccountId: nil))
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.repos.first?.primaryAccountId, first)
    }

    func test_add_usesExplicitAccountId_overSuggestionAndFirst() async throws {
        // The add-repo sheet resolves/lets the user pick a specific account;
        // that choice must win over both the detector's host suggestion and the
        // first-account fallback.
        let db = try makeDB()
        _ = try insertAccount(db, login: "aaa-first")     // first fallback
        let suggested = try insertAccount(db, login: "suggested")
        let chosen = try insertAccount(db, login: "chosen")

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let ok = await vm.add(detected(suggestedAccountId: suggested), accountId: chosen)
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.repos.first?.primaryAccountId, chosen)
    }

    func test_add_assignsNextSortOrder() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        try await insertRepo(db, accountId: acct, name: "Existing", repo: "existing", sortOrder: 5)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let ok = await vm.add(detected(path: "/tmp/New", owner: "o", repo: "new"))
        XCTAssertTrue(ok)

        let added = try await db.repos.all().first { $0.name == "New" }
        XCTAssertEqual(added?.sortOrder, 6)
    }

    func test_add_returnsFalse_whenNoAccounts() async throws {
        let db = try makeDB()   // no accounts inserted

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let ok = await vm.add(detected(suggestedAccountId: nil))
        XCTAssertFalse(ok)
        XCTAssertEqual(vm.repos.count, 0)
        XCTAssertNotNil(vm.error)
    }

    func test_add_postsReposDidChange() async throws {
        let db = try makeDB()
        try insertAccount(db)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let exp = expectation(forNotification: .aerieReposDidChange, object: nil)

        let ok = await vm.add(detected(path: "/tmp/New", owner: "o", repo: "new"))
        XCTAssertTrue(ok)

        await fulfillment(of: [exp], timeout: 1.0)
    }

    func test_add_failure_doesNotPostReposDidChange() async throws {
        let db = try makeDB()   // no accounts → add fails

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let exp = expectation(forNotification: .aerieReposDidChange, object: nil)
        exp.isInverted = true

        let ok = await vm.add(detected(suggestedAccountId: nil))
        XCTAssertFalse(ok)

        await fulfillment(of: [exp], timeout: 0.3)
    }

    func test_remove_postsReposDidChange() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let a = try await insertRepo(db, accountId: acct, name: "Alpha", repo: "alpha", sortOrder: 0)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let exp = expectation(forNotification: .aerieReposDidChange, object: nil)
        await vm.remove(id: a.id)
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func test_setAccount_updatesRepo_whenAccountExists() async throws {
        let db = try makeDB()
        let acct1 = try insertAccount(db, login: "first")
        let acct2 = try insertAccount(db, login: "second")
        let r = try await insertRepo(db, accountId: acct1)

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        let result = await vm.setAccount(repoId: r.id, accountId: acct2)
        XCTAssertTrue(result)

        let found = try await db.repos.find(id: r.id)
        XCTAssertEqual(found?.primaryAccountId, acct2)
        // Also reflected in VM state after refresh inside setAccount.
        XCTAssertEqual(vm.repos.first?.primaryAccountId, acct2)
    }
}
