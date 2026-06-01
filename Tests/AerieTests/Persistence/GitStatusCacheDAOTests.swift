import XCTest
import GRDB
@testable import Aerie

final class GitStatusCacheDAOTests: XCTestCase {
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

    private func makeStatus(repoId: UUID, branch: String = "main", isDirty: Bool = false) -> LocalGitStatus {
        LocalGitStatus(
            repoId: repoId,
            currentBranch: branch,
            isDirty: isDirty,
            dirtyFileCount: isDirty ? 3 : 0,
            aheadOfDefault: 1,
            behindOfDefault: 0,
            unpushedCommits: 1,
            originDefaultSha: "abc1234",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Tests

    func test_upsert_thenLookup() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let status = makeStatus(repoId: repo.id, branch: "main", isDirty: false)
        try await db.gitStatusCache.upsert(status)

        let fetched = try await db.gitStatusCache.status(forRepo: repo.id)
        XCTAssertEqual(fetched, status)
    }

    func test_upsert_replacesOlder() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let initial = makeStatus(repoId: repo.id, branch: "main", isDirty: false)
        try await db.gitStatusCache.upsert(initial)

        let updated = makeStatus(repoId: repo.id, branch: "feat/new", isDirty: true)
        try await db.gitStatusCache.upsert(updated)

        let fetched = try await db.gitStatusCache.status(forRepo: repo.id)
        XCTAssertEqual(fetched, updated)
        XCTAssertEqual(fetched?.currentBranch, "feat/new")
        XCTAssertEqual(fetched?.isDirty, true)
    }

    func test_status_returnsNilForUnknown() async throws {
        let db = try makeDB()
        let fetched = try await db.gitStatusCache.status(forRepo: UUID())
        XCTAssertNil(fetched)
    }
}
