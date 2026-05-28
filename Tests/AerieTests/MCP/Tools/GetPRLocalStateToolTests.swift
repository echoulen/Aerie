import XCTest
import GRDB
@testable import Aerie

final class GetPRLocalStateToolTests: XCTestCase {
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

    func test_handle_returnsCachedState() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let prId = UUID()
        let state = PRLocalState(
            prId: prId,
            sourceBranch: "feat/x",
            localBranchExists: true,
            isCurrentBranch: true,
            dirty: true,
            ahead: 2,
            behind: 1,
            unpushed: 0
        )
        try await db.prLocalStateCache.upsert(state, repoId: repo.id)

        let tool = GetPRLocalStateTool(db: db)
        let result = try await tool.handle(
            params: .object(["pr_id": .string(prId.uuidString)])
        )

        guard case .object(let obj) = result else {
            XCTFail("expected .object, got \(result)")
            return
        }
        XCTAssertEqual(obj["sourceBranch"], .string("feat/x"))
        XCTAssertEqual(obj["localBranchExists"], .bool(true))
        XCTAssertEqual(obj["isCurrentBranch"], .bool(true))
        XCTAssertEqual(obj["dirty"], .bool(true))
        XCTAssertEqual(obj["ahead"], .int(2))
        XCTAssertEqual(obj["behind"], .int(1))
        XCTAssertEqual(obj["unpushed"], .int(0))
    }

    func test_handle_unknownPRId_returnsNull() async throws {
        let db = try makeDB()
        let tool = GetPRLocalStateTool(db: db)
        let result = try await tool.handle(
            params: .object(["pr_id": .string(UUID().uuidString)])
        )
        XCTAssertEqual(result, .null)
    }

    func test_handle_missingPRId_throwsInvalidParams() async throws {
        let db = try makeDB()
        let tool = GetPRLocalStateTool(db: db)
        do {
            _ = try await tool.handle(params: .object([:]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isFalse() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        let db = try! AppDatabase(url: url)
        let tool = GetPRLocalStateTool(db: db)
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_get_pr_local_state")
    }
}
