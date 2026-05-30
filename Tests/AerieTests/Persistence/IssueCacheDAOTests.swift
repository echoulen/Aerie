import XCTest
import GRDB
@testable import Aerie

final class IssueCacheDAOTests: XCTestCase {
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

    private func makeIssue(
        repoId: UUID,
        number: Int,
        title: String = "Some issue"
    ) -> Issue {
        Issue(
            id: UUID(),
            repoId: repoId,
            number: number,
            title: title,
            authorLogin: "carlos-li",
            assignedToMe: true,
            labels: [IssueLabel(name: "bug", color: "d73a4a")],
            commentCount: 3,
            htmlUrl: URL(string: "https://github.com/octocat/hello-world/issues/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Tests

    func test_upsert_storesIssues() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        let issues = [
            makeIssue(repoId: repo.id, number: 1, title: "First"),
            makeIssue(repoId: repo.id, number: 2, title: "Second"),
        ]
        try await db.issueCache.upsert(issues, for: repo.id)

        let fetched = try await db.issueCache.issues(forRepo: repo.id)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(Set(fetched.map { $0.number }), Set([1, 2]))
        let first = fetched.first(where: { $0.number == 1 })
        XCTAssertEqual(first?.title, "First")
        XCTAssertEqual(first?.labels, [IssueLabel(name: "bug", color: "d73a4a")])
        XCTAssertEqual(first?.assignedToMe, true)
    }

    func test_upsert_replacesPriorSet() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.issueCache.upsert(
            [makeIssue(repoId: repo.id, number: 1), makeIssue(repoId: repo.id, number: 2)],
            for: repo.id
        )

        try await db.issueCache.upsert(
            [makeIssue(repoId: repo.id, number: 4, title: "Four")],
            for: repo.id
        )

        let fetched = try await db.issueCache.issues(forRepo: repo.id)
        XCTAssertEqual(fetched.map(\.number), [4])
    }

    func test_issuesForRepo_returnsEmptyForUnknown() async throws {
        let db = try makeDB()
        let issues = try await db.issueCache.issues(forRepo: UUID())
        XCTAssertTrue(issues.isEmpty)
    }

    func test_clear_removesAllForRepo() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.issueCache.upsert(
            [makeIssue(repoId: repo.id, number: 1), makeIssue(repoId: repo.id, number: 2)],
            for: repo.id
        )

        try await db.issueCache.clear(forRepo: repo.id)
        let fetched = try await db.issueCache.issues(forRepo: repo.id)
        XCTAssertTrue(fetched.isEmpty)
    }
}
