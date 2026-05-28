import XCTest
import GRDB
@testable import Aerie

final class GetLocalStatusToolTests: XCTestCase {
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

    private func insertRepo(_ db: AppDatabase, accountId: UUID) async throws -> Repository {
        let r = Repository(
            id: UUID(),
            name: "Example",
            localPath: URL(fileURLWithPath: "/tmp/example"),
            githubOwner: "octocat",
            githubRepo: "hello-world",
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: 0,
            hidden: false
        )
        try await db.repos.insert(r)
        return r
    }

    // MARK: - Tests

    func test_handle_returnsCachedStatus() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let status = LocalGitStatus(
            repoId: repo.id,
            currentBranch: "feat/x",
            isDirty: true,
            dirtyFileCount: 3,
            aheadOfDefault: 2,
            behindOfDefault: 1,
            unpushedCommits: 2,
            originDefaultSha: "abcdef1",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await db.gitStatusCache.upsert(status)

        let tool = GetLocalStatusTool(db: db)
        let result = try await tool.handle(
            params: .object(["repo_id": .string(repo.id.uuidString)])
        )

        guard case .object(let obj) = result else {
            XCTFail("expected .object, got \(result)")
            return
        }
        XCTAssertEqual(obj["currentBranch"], .string("feat/x"))
        XCTAssertEqual(obj["isDirty"], .bool(true))
        XCTAssertEqual(obj["dirtyFileCount"], .int(3))
        XCTAssertEqual(obj["aheadOfDefault"], .int(2))
        XCTAssertEqual(obj["behindOfDefault"], .int(1))
        XCTAssertEqual(obj["unpushedCommits"], .int(2))
        XCTAssertEqual(obj["originDefaultSha"], .string("abcdef1"))
    }

    func test_handle_unknownRepoId_returnsNull() async throws {
        let db = try makeDB()
        let tool = GetLocalStatusTool(db: db)
        let result = try await tool.handle(
            params: .object(["repo_id": .string(UUID().uuidString)])
        )
        XCTAssertEqual(result, .null)
    }

    func test_handle_missingRepoId_throwsInvalidParams() async throws {
        let db = try makeDB()
        let tool = GetLocalStatusTool(db: db)
        do {
            _ = try await tool.handle(params: .object([:]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_handle_invalidUUID_throwsInvalidParams() async throws {
        let db = try makeDB()
        let tool = GetLocalStatusTool(db: db)
        do {
            _ = try await tool.handle(
                params: .object(["repo_id": .string("not-a-uuid")])
            )
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isFalse() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        let db = try! AppDatabase(url: url)
        let tool = GetLocalStatusTool(db: db)
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_get_local_status")
    }
}
