import XCTest
import GRDB
@testable import Aerie

final class MergedBranchCacheDAOTests: XCTestCase {
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
            id: UUID(), name: "Example",
            localPath: URL(fileURLWithPath: "/tmp/example"),
            githubOwner: "octocat", githubRepo: "hello-world",
            defaultBranch: "main", primaryAccountId: accountId,
            sortOrder: 0, hidden: false
        )
        try await db.repos.insert(r)
        return r
    }

    private func makeInfo(repoId: UUID, branch: String = "IOE-3017", number: Int = 62) -> MergedBranchInfo {
        MergedBranchInfo(
            repoId: repoId, branch: branch, prNumber: number,
            prUrl: URL(string: "https://github.com/octocat/hello-world/pull/\(number)")!,
            headOid: "abc1234", mergedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func test_upsert_thenLookup() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let info = makeInfo(repoId: repo.id)
        try await db.mergedBranchCache.upsert(info)

        let fetched = try await db.mergedBranchCache.info(forRepo: repo.id)
        XCTAssertEqual(fetched, info)
    }

    func test_upsert_replacesOlder() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.mergedBranchCache.upsert(makeInfo(repoId: repo.id, branch: "old", number: 1))
        try await db.mergedBranchCache.upsert(makeInfo(repoId: repo.id, branch: "new", number: 2))

        let fetched = try await db.mergedBranchCache.info(forRepo: repo.id)
        XCTAssertEqual(fetched?.prNumber, 2)
        XCTAssertEqual(fetched?.branch, "new")
    }

    func test_clear_removesEntry() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.mergedBranchCache.upsert(makeInfo(repoId: repo.id))
        try await db.mergedBranchCache.clear(forRepo: repo.id)

        let fetched = try await db.mergedBranchCache.info(forRepo: repo.id)
        XCTAssertNil(fetched)
    }

    func test_info_returnsNilForUnknown() async throws {
        let db = try makeDB()
        let fetched = try await db.mergedBranchCache.info(forRepo: UUID())
        XCTAssertNil(fetched)
    }
}
