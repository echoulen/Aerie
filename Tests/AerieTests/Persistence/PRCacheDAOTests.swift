import XCTest
import GRDB
@testable import Aerie

final class PRCacheDAOTests: XCTestCase {
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

    private func makePR(
        repoId: UUID,
        number: Int,
        title: String = "Some PR"
    ) -> PullRequest {
        PullRequest(
            id: UUID(),
            repoId: repoId,
            number: number,
            title: title,
            authorLogin: "carlos-li",
            sourceBranch: "feat/x",
            isMine: true,
            state: .open,
            ciState: .pending,
            reviewState: .reviewRequired,
            labels: ["enhancement"],
            htmlUrl: URL(string: "https://github.com/octocat/hello-world/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Tests

    func test_upsert_storesPRs() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let prs = [
            makePR(repoId: repo.id, number: 1, title: "First"),
            makePR(repoId: repo.id, number: 2, title: "Second"),
        ]
        try await db.prCache.upsert(prs, for: repo.id)

        let fetched = try await db.prCache.prs(forRepo: repo.id)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(Set(fetched.map { $0.number }), Set([1, 2]))
        XCTAssertEqual(fetched.first(where: { $0.number == 1 })?.title, "First")
    }

    func test_upsert_replacesPriorSet() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let initial = [
            makePR(repoId: repo.id, number: 1),
            makePR(repoId: repo.id, number: 2),
            makePR(repoId: repo.id, number: 3),
        ]
        try await db.prCache.upsert(initial, for: repo.id)

        let next = [
            makePR(repoId: repo.id, number: 4, title: "Four"),
            makePR(repoId: repo.id, number: 5, title: "Five"),
        ]
        try await db.prCache.upsert(next, for: repo.id)

        let fetched = try await db.prCache.prs(forRepo: repo.id)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(Set(fetched.map { $0.number }), Set([4, 5]))
    }

    func test_prsForRepo_returnsEmptyForUnknown() async throws {
        let db = try makeDB()
        let prs = try await db.prCache.prs(forRepo: UUID())
        XCTAssertTrue(prs.isEmpty)
    }

    func test_clear_removesAllForRepo() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.prCache.upsert(
            [makePR(repoId: repo.id, number: 1), makePR(repoId: repo.id, number: 2)],
            for: repo.id
        )

        try await db.prCache.clear(forRepo: repo.id)
        let fetched = try await db.prCache.prs(forRepo: repo.id)
        XCTAssertTrue(fetched.isEmpty)
    }
}
