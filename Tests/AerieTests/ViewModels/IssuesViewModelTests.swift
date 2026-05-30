import XCTest
import GRDB
@testable import Aerie

final class IssuesViewModelTests: XCTestCase {
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

    private func insertRepo(
        _ db: AppDatabase,
        accountId: UUID,
        name: String = "Example",
        owner: String = "octocat",
        repo: String = "hello-world",
        hidden: Bool = false
    ) async throws -> Repository {
        let r = Repository(
            id: UUID(),
            name: name,
            localPath: URL(fileURLWithPath: "/tmp/\(name)"),
            githubOwner: owner,
            githubRepo: repo,
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: 0,
            hidden: hidden
        )
        try await db.repos.insert(r)
        return r
    }

    private func makeIssue(
        repoId: UUID,
        number: Int,
        title: String = "Some issue",
        assignedToMe: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Issue {
        Issue(
            id: UUID(),
            repoId: repoId,
            number: number,
            title: title,
            authorLogin: "carlos-li",
            assignedToMe: assignedToMe,
            labels: [],
            commentCount: 0,
            htmlUrl: URL(string: "https://github.com/octocat/hello-world/issues/\(number)")!,
            updatedAt: updatedAt
        )
    }

    // MARK: - Tests

    func test_refresh_emitsReady_withFlattenedSortedRows() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repoA = try await insertRepo(db, accountId: acct, name: "Alpha")
        let repoB = try await insertRepo(db, accountId: acct, name: "Bravo", repo: "bravo")

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let a1 = makeIssue(repoId: repoA.id, number: 1, updatedAt: base.addingTimeInterval(10))
        let a2 = makeIssue(repoId: repoA.id, number: 2, updatedAt: base.addingTimeInterval(40))
        let b1 = makeIssue(repoId: repoB.id, number: 3, updatedAt: base.addingTimeInterval(20))
        let b2 = makeIssue(repoId: repoB.id, number: 4, updatedAt: base.addingTimeInterval(30))

        try await db.issueCache.upsert([a1, a2], for: repoA.id)
        try await db.issueCache.upsert([b1, b2], for: repoB.id)

        let vm = IssuesViewModel(db: db)
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.count, 4)
        // Sorted descending by updatedAt: a2 (40), b2 (30), b1 (20), a1 (10).
        XCTAssertEqual(rows.map { $0.issue.number }, [2, 4, 3, 1])
    }

    func test_refresh_emitsEmpty_whenNoRepos() async throws {
        let db = try makeDB()
        let vm = IssuesViewModel(db: db)
        await vm.refresh()
        XCTAssertEqual(vm.state, .empty)
    }

    func test_refresh_emitsEmpty_whenReposButNoIssues() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        _ = try await insertRepo(db, accountId: acct)

        let vm = IssuesViewModel(db: db)
        await vm.refresh()
        XCTAssertEqual(vm.state, .empty)
    }

    func test_refresh_excludesHiddenRepos() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let visible = try await insertRepo(db, accountId: acct, name: "Visible")
        let hidden = try await insertRepo(db, accountId: acct, name: "Hidden", repo: "hidden", hidden: true)

        try await db.issueCache.upsert([makeIssue(repoId: visible.id, number: 1, title: "V1")], for: visible.id)
        try await db.issueCache.upsert([makeIssue(repoId: hidden.id, number: 9, title: "Hidden")], for: hidden.id)

        let vm = IssuesViewModel(db: db)
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].issue.number, 1)
        XCTAssertEqual(rows[0].repo.id, visible.id)
    }

    func test_refresh_countsAssignedToMe() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.issueCache.upsert(
            [
                makeIssue(repoId: repo.id, number: 1, assignedToMe: true),
                makeIssue(repoId: repo.id, number: 2, assignedToMe: false),
                makeIssue(repoId: repo.id, number: 3, assignedToMe: true),
            ],
            for: repo.id
        )

        let vm = IssuesViewModel(db: db)
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.filter { $0.issue.assignedToMe }.count, 2)
    }
}
