import XCTest
import GRDB
@testable import Aerie

final class GetPRDiffToolTests: XCTestCase {
    private var tempURLs: [URL] = []
    override func tearDownWithError() throws {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs.removeAll()
    }
    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }
    @discardableResult
    private func insertAccount(_ db: AppDatabase, id: UUID = UUID()) throws -> UUID {
        try db.dbQueue.write { c in
            try c.execute(sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                          arguments: [id.uuidString, "tester", "github.com"])
        }
        return id
    }
    private func insertRepo(_ db: AppDatabase, accountId: UUID) async throws -> Repository {
        let r = Repository(id: UUID(), name: "R", localPath: URL(fileURLWithPath: "/tmp/r"),
                           githubOwner: "octocat", githubRepo: "hello-world", defaultBranch: "main",
                           primaryAccountId: accountId, sortOrder: 0, hidden: false)
        try await db.repos.insert(r)
        return r
    }

    func test_handle_returnsFiles() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let token = "tok"
        let stub = StubGitHubAPIClient()
        await stub.setPRFiles(
            [PRFileChange(filename: "a.swift", status: .modified, additions: 3, deletions: 1, patch: "@@ -1 +1 @@\n-old\n+new")],
            forToken: token)
        let api = MultiAccountAPI(client: stub, tokensByAccount: { [acct: token] }, accountsInOrder: { [acct] })

        let tool = GetPRDiffTool(db: db, api: api)
        let result = try await tool.handle(params: .object([
            "repo_id": .string(repo.id.uuidString), "number": .int(7),
        ]))

        guard case .object(let obj) = result, case .array(let files) = obj["files"] ?? .null else {
            return XCTFail("expected .files array, got \(result)")
        }
        XCTAssertEqual(files.count, 1)
        guard case .object(let f) = files[0] else { return XCTFail("file not object") }
        XCTAssertEqual(f["filename"], .string("a.swift"))
        XCTAssertEqual(f["status"], .string("modified"))
        XCTAssertEqual(f["additions"], .int(3))
        XCTAssertEqual(f["deletions"], .int(1))
        XCTAssertEqual(f["patch"], .string("@@ -1 +1 @@\n-old\n+new"))
    }

    func test_handle_unknownRepo_throwsInvalidParams() async throws {
        let db = try makeDB()
        let api = MultiAccountAPI(client: StubGitHubAPIClient(), tokensByAccount: { [:] }, accountsInOrder: { [] })
        let tool = GetPRDiffTool(db: db, api: api)
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(UUID().uuidString), "number": .int(1)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_handle_apiError_throwsMinus32010() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let token = "tok"
        let stub = StubGitHubAPIClient()
        await stub.setPRFilesError(GitHubAPIError(status: 404, message: "not found"), forToken: token)
        let api = MultiAccountAPI(client: stub, tokensByAccount: { [acct: token] }, accountsInOrder: { [acct] })
        let tool = GetPRDiffTool(db: db, api: api)
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(repo.id.uuidString), "number": .int(7)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32010)
        }
    }

    func test_isWrite_isFalse() throws {
        let db = try makeDB()
        let api = MultiAccountAPI(client: StubGitHubAPIClient(), tokensByAccount: { [:] }, accountsInOrder: { [] })
        let tool = GetPRDiffTool(db: db, api: api)
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_get_pr_diff")
    }
}
