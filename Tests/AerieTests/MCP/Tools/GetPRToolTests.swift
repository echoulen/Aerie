import XCTest
import GRDB
@testable import Aerie

final class GetPRToolTests: XCTestCase {
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

    private func makePR(repoId: UUID, number: Int) -> PullRequest {
        PullRequest(
            id: UUID(),
            repoId: repoId,
            number: number,
            title: "PR #\(number)",
            authorLogin: "ghost",
            sourceBranch: "feat/x",
            isMine: false,
            state: .open,
            ciState: .pending,
            reviewState: .reviewRequired,
            labels: ["bug"],
            htmlUrl: URL(string: "https://github.com/octocat/hello-world/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Tests

    func test_handle_returnsMatchingPR() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let pr = makePR(repoId: repo.id, number: 42)
        try await db.prCache.upsert([pr], for: repo.id)

        let tool = GetPRTool(db: db)
        let result = try await tool.handle(
            params: .object([
                "repo_id": .string(repo.id.uuidString),
                "number": .int(42),
            ])
        )

        guard case .object(let obj) = result else {
            XCTFail("expected .object, got \(result)")
            return
        }
        XCTAssertEqual(obj["number"], .int(42))
        XCTAssertEqual(obj["title"], .string("PR #42"))
    }

    func test_handle_unknownNumber_returnsNull() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.prCache.upsert([makePR(repoId: repo.id, number: 1)], for: repo.id)

        let tool = GetPRTool(db: db)
        let result = try await tool.handle(
            params: .object([
                "repo_id": .string(repo.id.uuidString),
                "number": .int(999),
            ])
        )
        XCTAssertEqual(result, .null)
    }

    func test_handle_missingNumber_throwsInvalidParams() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)

        let tool = GetPRTool(db: db)
        do {
            _ = try await tool.handle(
                params: .object(["repo_id": .string(repo.id.uuidString)])
            )
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_handle_missingRepoId_throwsInvalidParams() async throws {
        let db = try makeDB()
        let tool = GetPRTool(db: db)
        do {
            _ = try await tool.handle(params: .object(["number": .int(1)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isFalse() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        let db = try! AppDatabase(url: url)
        let tool = GetPRTool(db: db)
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_get_pr")
    }
}
