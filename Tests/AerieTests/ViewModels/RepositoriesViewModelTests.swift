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
