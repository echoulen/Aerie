import XCTest
import GRDB
@testable import Aerie

final class AccountDAOTests: XCTestCase {
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

    private func makeAccount(
        id: UUID = UUID(),
        login: String = "tester",
        host: String = "github.com"
    ) -> GitHubAccount {
        GitHubAccount(id: id, login: login, host: host)
    }

    // MARK: - Tests

    func test_insertAndFetchAll() async throws {
        let db = try makeDB()
        let a = makeAccount(login: "alice")
        let b = makeAccount(login: "bob")
        try await db.accounts.insert(a)
        try await db.accounts.insert(b)

        let all = try await db.accounts.all()
        XCTAssertEqual(all.count, 2)
        // Sorted by login then host.
        XCTAssertEqual(all.map { $0.login }, ["alice", "bob"])
    }

    func test_all_sortedByLoginThenHost() async throws {
        let db = try makeDB()
        let a1 = makeAccount(login: "alice", host: "github.com")
        let a2 = makeAccount(login: "alice", host: "ghe.example.com")
        let z = makeAccount(login: "zoe", host: "github.com")
        try await db.accounts.insert(z)
        try await db.accounts.insert(a1)
        try await db.accounts.insert(a2)

        let all = try await db.accounts.all()
        XCTAssertEqual(all.map { "\($0.login)@\($0.host)" },
                       ["alice@ghe.example.com", "alice@github.com", "zoe@github.com"])
    }

    func test_findByLoginHost_returnsMatch() async throws {
        let db = try makeDB()
        let a = makeAccount(login: "alice", host: "github.com")
        try await db.accounts.insert(a)

        let found = try await db.accounts.find(login: "alice", host: "github.com")
        XCTAssertEqual(found, a)
    }

    func test_findByLoginHost_returnsNilWhenAbsent() async throws {
        let db = try makeDB()
        let found = try await db.accounts.find(login: "nobody", host: "github.com")
        XCTAssertNil(found)
    }

    func test_delete_removesRow() async throws {
        let db = try makeDB()
        let a = makeAccount(login: "alice")
        try await db.accounts.insert(a)
        try await db.accounts.delete(id: a.id)

        let all = try await db.accounts.all()
        XCTAssertTrue(all.isEmpty)
    }

    func test_unique_loginHost_rejectsDuplicate() async throws {
        let db = try makeDB()
        let a = makeAccount(login: "alice", host: "github.com")
        let dup = makeAccount(id: UUID(), login: "alice", host: "github.com")
        try await db.accounts.insert(a)

        do {
            try await db.accounts.insert(dup)
            XCTFail("Expected UNIQUE constraint violation")
        } catch {
            // Expected — SQLite should throw on UNIQUE(login, host) violation.
        }
    }
}
