import XCTest
import GRDB
@testable import Aerie

final class ListReposToolTests: XCTestCase {
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

    // MARK: - Tests

    func test_handle_returnsAllRepos() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r1 = Repository(
            id: UUID(),
            name: "Alpha",
            localPath: URL(fileURLWithPath: "/tmp/alpha"),
            githubOwner: "octocat",
            githubRepo: "alpha",
            defaultBranch: "main",
            primaryAccountId: acct,
            sortOrder: 0,
            hidden: false
        )
        let r2 = Repository(
            id: UUID(),
            name: "Bravo",
            localPath: URL(fileURLWithPath: "/tmp/bravo"),
            githubOwner: "octocat",
            githubRepo: "bravo",
            defaultBranch: "develop",
            primaryAccountId: acct,
            sortOrder: 1,
            hidden: true,
            apiSyncDisabled: true
        )
        try await db.repos.insert(r1)
        try await db.repos.insert(r2)

        let tool = ListReposTool(db: db)
        let result = try await tool.handle(params: nil)

        guard case .object(let obj) = result,
              case .array(let items) = obj["repos"] ?? .null else {
            XCTFail("expected .object with .repos array, got \(result)")
            return
        }
        XCTAssertEqual(items.count, 2)

        guard case .object(let first) = items[0] else {
            XCTFail("expected first entry to be object")
            return
        }
        XCTAssertEqual(first["id"], .string(r1.id.uuidString))
        XCTAssertEqual(first["name"], .string("Alpha"))
        XCTAssertEqual(first["local_path"], .string("/tmp/alpha"))
        XCTAssertEqual(first["owner"], .string("octocat"))
        XCTAssertEqual(first["repo"], .string("alpha"))
        XCTAssertEqual(first["default_branch"], .string("main"))
        XCTAssertEqual(first["hidden"], .bool(false))
        XCTAssertEqual(first["api_sync_disabled"], .bool(false))

        guard case .object(let second) = items[1] else {
            XCTFail("expected second entry to be object")
            return
        }
        XCTAssertEqual(second["name"], .string("Bravo"))
        XCTAssertEqual(second["default_branch"], .string("develop"))
        XCTAssertEqual(second["hidden"], .bool(true))
        XCTAssertEqual(second["api_sync_disabled"], .bool(true))
    }

    func test_handle_emptyDB_returnsEmptyArray() async throws {
        let db = try makeDB()
        let tool = ListReposTool(db: db)
        let result = try await tool.handle(params: nil)
        guard case .object(let obj) = result,
              case .array(let items) = obj["repos"] ?? .null else {
            XCTFail("expected .object with .repos array")
            return
        }
        XCTAssertEqual(items.count, 0)
    }

    func test_isWrite_isFalse() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        let db = try! AppDatabase(url: url)
        let tool = ListReposTool(db: db)
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_list_repos")
    }
}
