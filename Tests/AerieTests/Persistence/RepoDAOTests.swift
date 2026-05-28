import XCTest
import GRDB
@testable import Aerie

final class RepoDAOTests: XCTestCase {
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
    private func insertAccount(_ db: AppDatabase, id: UUID = UUID(), login: String = "tester") throws -> UUID {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [id.uuidString, login, "github.com"]
            )
        }
        return id
    }

    private func makeRepo(
        id: UUID = UUID(),
        name: String = "Example",
        accountId: UUID,
        sortOrder: Int = 0,
        hidden: Bool = false,
        owner: String = "octocat",
        repo: String = "hello-world",
        defaultBranch: String = "main",
        localPath: URL = URL(fileURLWithPath: "/tmp/example")
    ) -> Repository {
        Repository(
            id: id,
            name: name,
            localPath: localPath,
            githubOwner: owner,
            githubRepo: repo,
            defaultBranch: defaultBranch,
            primaryAccountId: accountId,
            sortOrder: sortOrder,
            hidden: hidden
        )
    }

    // MARK: - Tests

    func test_insertAndFetchAll() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r = makeRepo(accountId: acct)
        try await db.repos.insert(r)

        let all = try await db.repos.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, r.id)
        XCTAssertEqual(all.first, r)
    }

    func test_find_returnsInserted() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r = makeRepo(name: "FindMe", accountId: acct)
        try await db.repos.insert(r)

        let found = try await db.repos.find(id: r.id)
        XCTAssertEqual(found, r)
    }

    func test_find_returnsNilForUnknown() async throws {
        let db = try makeDB()
        let found = try await db.repos.find(id: UUID())
        XCTAssertNil(found)
    }

    func test_update_changesPersistedFields() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        var r = makeRepo(name: "Old", accountId: acct)
        try await db.repos.insert(r)

        r.name = "New"
        r.defaultBranch = "develop"
        r.sortOrder = 42
        r.hidden = true
        r.localPath = URL(fileURLWithPath: "/var/tmp/elsewhere")
        try await db.repos.update(r)

        let found = try await db.repos.find(id: r.id)
        XCTAssertEqual(found?.name, "New")
        XCTAssertEqual(found?.defaultBranch, "develop")
        XCTAssertEqual(found?.sortOrder, 42)
        XCTAssertEqual(found?.hidden, true)
        XCTAssertEqual(found?.localPath, URL(fileURLWithPath: "/var/tmp/elsewhere"))
    }

    func test_delete_removesRow() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r = makeRepo(accountId: acct)
        try await db.repos.insert(r)
        try await db.repos.delete(id: r.id)

        let all = try await db.repos.all()
        XCTAssertTrue(all.isEmpty)
        let found = try await db.repos.find(id: r.id)
        XCTAssertNil(found)
    }

    func test_setHidden_togglesFlag() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r = makeRepo(accountId: acct, hidden: false)
        try await db.repos.insert(r)

        try await db.repos.setHidden(id: r.id, true)
        let afterTrue = try await db.repos.find(id: r.id)
        XCTAssertEqual(afterTrue?.hidden, true)

        try await db.repos.setHidden(id: r.id, false)
        let afterFalse = try await db.repos.find(id: r.id)
        XCTAssertEqual(afterFalse?.hidden, false)
    }

    func test_setSortOrder_updatesOrder() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r = makeRepo(accountId: acct, sortOrder: 0)
        try await db.repos.insert(r)

        try await db.repos.setSortOrder(id: r.id, 99)
        let found = try await db.repos.find(id: r.id)
        XCTAssertEqual(found?.sortOrder, 99)
    }

    func test_setName_updatesName() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r = makeRepo(name: "Before", accountId: acct)
        try await db.repos.insert(r)

        try await db.repos.setName(id: r.id, "After")
        let found = try await db.repos.find(id: r.id)
        XCTAssertEqual(found?.name, "After")
    }

    func test_setAccount_updatesAccountId() async throws {
        let db = try makeDB()
        let acct1 = try insertAccount(db, login: "first")
        let acct2 = try insertAccount(db, login: "second")
        let r = makeRepo(accountId: acct1)
        try await db.repos.insert(r)

        try await db.repos.setAccount(id: r.id, acct2)
        let found = try await db.repos.find(id: r.id)
        XCTAssertEqual(found?.primaryAccountId, acct2)
    }

    func test_all_sortedBySortOrderThenName() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        // Insert out of order on purpose.
        let rB1 = makeRepo(name: "Bravo", accountId: acct, sortOrder: 1)
        let rA1 = makeRepo(name: "Alpha", accountId: acct, sortOrder: 1)
        let rZ0 = makeRepo(name: "Zulu", accountId: acct, sortOrder: 0)
        try await db.repos.insert(rB1)
        try await db.repos.insert(rA1)
        try await db.repos.insert(rZ0)

        let all = try await db.repos.all()
        XCTAssertEqual(all.map { $0.name }, ["Zulu", "Alpha", "Bravo"])
    }
}
