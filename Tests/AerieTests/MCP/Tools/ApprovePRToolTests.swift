import XCTest
import GRDB
@testable import Aerie

final class ApprovePRToolTests: XCTestCase {
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
    private func insertAccount(_ db: AppDatabase, id: UUID, login: String) throws -> UUID {
        try db.dbQueue.write { c in
            try c.execute(sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                          arguments: [id.uuidString, login, "github.com"])
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
    private func makePR(repoId: UUID, number: Int, author: String) -> PullRequest {
        PullRequest(id: UUID(), repoId: repoId, number: number, title: "PR", authorLogin: author,
                    sourceBranch: "feat/x", isMine: false, state: .open, ciState: .success,
                    reviewState: .reviewRequired, labels: [],
                    htmlUrl: URL(string: "https://github.com/o/r/pull/\(number)")!,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    final class RefreshSpy: @unchecked Sendable {
        private let lock = NSLock(); private var _ids: [UUID] = []
        var ids: [UUID] { lock.lock(); defer { lock.unlock() }; return _ids }
        func record(_ id: UUID) { lock.lock(); defer { lock.unlock() }; _ids.append(id) }
    }

    func test_handle_approvesAsBoundAccount_whenNotAuthor() async throws {
        let db = try makeDB()
        let boundId = UUID()
        _ = try insertAccount(db, id: boundId, login: "reviewer")
        let repo = try await insertRepo(db, accountId: boundId)
        try await db.prCache.upsert([makePR(repoId: repo.id, number: 7, author: "author-x")], for: repo.id)
        let token = "tok"
        let stub = StubGitHubAPIClient()
        let api = MultiAccountAPI(client: stub, tokensByAccount: { [boundId: token] }, accountsInOrder: { [boundId] })
        let accounts = [GitHubAccount(id: boundId, login: "reviewer", host: "github.com")]
        let spy = RefreshSpy()

        let tool = ApprovePRTool(db: db, api: api, accounts: { accounts }, refresh: { spy.record($0) })
        let result = try await tool.handle(params: .object([
            "repo_id": .string(repo.id.uuidString), "number": .int(7),
        ]))

        guard case .object(let obj) = result else { return XCTFail("expected object") }
        XCTAssertEqual(obj["approved"], .bool(true))
        XCTAssertEqual(obj["account_id"], .string(boundId.uuidString))
        XCTAssertEqual(obj["approver_login"], .string("reviewer"))
        let calls = await stub.approveCalls
        XCTAssertEqual(calls.map(\.token), [token])
        for _ in 0..<50 { if spy.ids.count == 1 { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(spy.ids, [repo.id])
    }

    func test_handle_noEligibleApprover_throwsMinus32010() async throws {
        // Only the author's account is connected → nobody may approve.
        let db = try makeDB()
        let authorId = UUID()
        _ = try insertAccount(db, id: authorId, login: "author-x")
        let repo = try await insertRepo(db, accountId: authorId)
        try await db.prCache.upsert([makePR(repoId: repo.id, number: 7, author: "author-x")], for: repo.id)
        let api = MultiAccountAPI(client: StubGitHubAPIClient(), tokensByAccount: { [authorId: "t"] }, accountsInOrder: { [authorId] })
        let accounts = [GitHubAccount(id: authorId, login: "author-x", host: "github.com")]
        let tool = ApprovePRTool(db: db, api: api, accounts: { accounts }, refresh: { _ in })
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(repo.id.uuidString), "number": .int(7)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32010)
        }
    }

    func test_handle_unknownPR_throwsInvalidParams() async throws {
        let db = try makeDB()
        let id = UUID()
        _ = try insertAccount(db, id: id, login: "reviewer")
        let repo = try await insertRepo(db, accountId: id)
        let api = MultiAccountAPI(client: StubGitHubAPIClient(), tokensByAccount: { [id: "t"] }, accountsInOrder: { [id] })
        let tool = ApprovePRTool(db: db, api: api, accounts: { [] }, refresh: { _ in })
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(repo.id.uuidString), "number": .int(99)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isTrue() throws {
        let db = try makeDB()
        let api = MultiAccountAPI(client: StubGitHubAPIClient(), tokensByAccount: { [:] }, accountsInOrder: { [] })
        let tool = ApprovePRTool(db: db, api: api, accounts: { [] }, refresh: { _ in })
        XCTAssertTrue(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_approve_pr")
    }
}
