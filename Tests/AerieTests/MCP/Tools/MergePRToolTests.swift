import XCTest
import GRDB
@testable import Aerie

final class MergePRToolTests: XCTestCase {
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

    /// Captures invocations of the post-merge refresh closure so tests can
    /// assert it was invoked exactly once with the expected repo id.
    final class RefreshSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _ids: [UUID] = []
        var ids: [UUID] {
            lock.lock(); defer { lock.unlock() }
            return _ids
        }
        func record(_ id: UUID) {
            lock.lock(); defer { lock.unlock() }
            _ids.append(id)
        }
    }

    // MARK: - Tests

    func test_handle_successfulMerge_returnsResultAndTriggersRefresh() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)

        let token = "tok"
        let stub = StubGitHubAPIClient()
        await stub.enqueue(.merge(MergeResult(sha: "deadbeef", merged: true)), forToken: token)
        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [acct: token] },
            accountsInOrder: { [acct] }
        )

        let spy = RefreshSpy()
        let tool = MergePRTool(db: db, api: api, refresh: { id in spy.record(id) })

        let result = try await tool.handle(
            params: .object([
                "repo_id": .string(repo.id.uuidString),
                "number": .int(7),
            ])
        )

        guard case .object(let obj) = result else {
            XCTFail("expected .object, got \(result)")
            return
        }
        XCTAssertEqual(obj["merged"], .bool(true))
        XCTAssertEqual(obj["sha"], .string("deadbeef"))
        XCTAssertEqual(obj["account_id"], .string(acct.uuidString))

        // Refresh is invoked detached — wait for its task to run.
        for _ in 0..<50 {
            if spy.ids.count == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(spy.ids, [repo.id])
    }

    func test_handle_unknownRepo_throwsInvalidParams() async throws {
        let db = try makeDB()
        let stub = StubGitHubAPIClient()
        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [:] },
            accountsInOrder: { [] }
        )
        let tool = MergePRTool(db: db, api: api, refresh: { _ in })

        do {
            _ = try await tool.handle(
                params: .object([
                    "repo_id": .string(UUID().uuidString),
                    "number": .int(1),
                ])
            )
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_handle_apiFailure_throwsMinus32010() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)

        let token = "tok"
        let stub = StubGitHubAPIClient()
        await stub.enqueue(
            .apiError(GitHubAPIError(status: 409, message: "merge conflict")),
            forToken: token
        )
        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [acct: token] },
            accountsInOrder: { [acct] }
        )
        let tool = MergePRTool(db: db, api: api, refresh: { _ in })

        do {
            _ = try await tool.handle(
                params: .object([
                    "repo_id": .string(repo.id.uuidString),
                    "number": .int(7),
                ])
            )
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32010)
            XCTAssertTrue(e.message.contains("merge conflict"), "got: \(e.message)")
        }
    }

    func test_handle_missingNumber_throwsInvalidParams() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let api = MultiAccountAPI(
            client: StubGitHubAPIClient(),
            tokensByAccount: { [:] },
            accountsInOrder: { [] }
        )
        let tool = MergePRTool(db: db, api: api, refresh: { _ in })

        do {
            _ = try await tool.handle(
                params: .object(["repo_id": .string(repo.id.uuidString)])
            )
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isTrue() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        let db = try! AppDatabase(url: url)
        let api = MultiAccountAPI(
            client: StubGitHubAPIClient(),
            tokensByAccount: { [:] },
            accountsInOrder: { [] }
        )
        let tool = MergePRTool(db: db, api: api, refresh: { _ in })
        XCTAssertTrue(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_merge_pr")
    }
}
