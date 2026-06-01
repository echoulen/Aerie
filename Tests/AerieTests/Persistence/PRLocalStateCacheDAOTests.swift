import XCTest
import GRDB
@testable import Aerie

final class PRLocalStateCacheDAOTests: XCTestCase {
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

    private func makeState(prId: UUID, sourceBranch: String = "feat/x", isCurrent: Bool = true) -> PRLocalState {
        PRLocalState(
            prId: prId,
            sourceBranch: sourceBranch,
            localBranchExists: true,
            isCurrentBranch: isCurrent,
            dirty: isCurrent ? true : nil,
            ahead: isCurrent ? 2 : nil,
            behind: isCurrent ? 1 : nil,
            unpushed: isCurrent ? 3 : nil
        )
    }

    // MARK: - Tests

    func test_upsert_thenLookup() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let prId = UUID()
        let state = makeState(prId: prId)
        try await db.prLocalStateCache.upsert(state, repoId: repo.id)

        let fetched = try await db.prLocalStateCache.state(forPr: prId)
        XCTAssertEqual(fetched, state)
    }

    func test_upsert_replacesOlder() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let prId = UUID()
        let initial = makeState(prId: prId, sourceBranch: "feat/old", isCurrent: false)
        try await db.prLocalStateCache.upsert(initial, repoId: repo.id)

        let replaced = makeState(prId: prId, sourceBranch: "feat/new", isCurrent: true)
        try await db.prLocalStateCache.upsert(replaced, repoId: repo.id)

        let fetched = try await db.prLocalStateCache.state(forPr: prId)
        XCTAssertEqual(fetched, replaced)
        XCTAssertEqual(fetched?.sourceBranch, "feat/new")
    }

    func test_state_returnsNilForUnknown() async throws {
        let db = try makeDB()
        let fetched = try await db.prLocalStateCache.state(forPr: UUID())
        XCTAssertNil(fetched)
    }
}
