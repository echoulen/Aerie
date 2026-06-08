import XCTest
import GRDB
@testable import Aerie

final class UpdatePRBranchToolTests: XCTestCase {
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
    final class RefreshSpy: @unchecked Sendable {
        private let lock = NSLock(); private var _ids: [UUID] = []
        var ids: [UUID] { lock.lock(); defer { lock.unlock() }; return _ids }
        func record(_ id: UUID) { lock.lock(); defer { lock.unlock() }; _ids.append(id) }
    }

    func test_handle_success_returnsUpdatedAndRefreshes() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let token = "tok"
        let stub = StubGitHubAPIClient()  // default update-branch = no-op success
        let api = MultiAccountAPI(client: stub, tokensByAccount: { [acct: token] }, accountsInOrder: { [acct] })
        let spy = RefreshSpy()
        let tool = UpdatePRBranchTool(db: db, api: api, refresh: { spy.record($0) })

        let result = try await tool.handle(params: .object([
            "repo_id": .string(repo.id.uuidString), "number": .int(7),
        ]))
        guard case .object(let obj) = result else { return XCTFail("expected object") }
        XCTAssertEqual(obj["updated"], .bool(true))
        let calls = await stub.updateBranchCalls
        XCTAssertEqual(calls, [token])
        for _ in 0..<50 { if spy.ids.count == 1 { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(spy.ids, [repo.id])
    }

    func test_handle_apiError_throwsMinus32010() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let token = "tok"
        let stub = StubGitHubAPIClient()
        await stub.setUpdateBranchError(GitHubAPIError(status: 422, message: "merge conflict"), forToken: token)
        let api = MultiAccountAPI(client: stub, tokensByAccount: { [acct: token] }, accountsInOrder: { [acct] })
        let tool = UpdatePRBranchTool(db: db, api: api, refresh: { _ in })
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(repo.id.uuidString), "number": .int(7)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32010)
        }
    }

    func test_handle_unknownRepo_throwsInvalidParams() async throws {
        let db = try makeDB()
        let api = MultiAccountAPI(client: StubGitHubAPIClient(), tokensByAccount: { [:] }, accountsInOrder: { [] })
        let tool = UpdatePRBranchTool(db: db, api: api, refresh: { _ in })
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(UUID().uuidString), "number": .int(1)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isTrue() throws {
        let db = try makeDB()
        let api = MultiAccountAPI(client: StubGitHubAPIClient(), tokensByAccount: { [:] }, accountsInOrder: { [] })
        let tool = UpdatePRBranchTool(db: db, api: api, refresh: { _ in })
        XCTAssertTrue(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_update_pr_branch")
    }
}
