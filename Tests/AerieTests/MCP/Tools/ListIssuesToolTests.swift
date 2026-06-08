import XCTest
import GRDB
@testable import Aerie

final class ListIssuesToolTests: XCTestCase {
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
        try db.dbQueue.write { c in
            try c.execute(sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                          arguments: [id.uuidString, login, "github.com"])
        }
        return id
    }
    private func insertRepo(_ db: AppDatabase, accountId: UUID, name: String) async throws -> Repository {
        let r = Repository(id: UUID(), name: name, localPath: URL(fileURLWithPath: "/tmp/\(name)"),
                           githubOwner: "octocat", githubRepo: name.lowercased(), defaultBranch: "main",
                           primaryAccountId: accountId, sortOrder: 0, hidden: false)
        try await db.repos.insert(r)
        return r
    }
    private func makeIssue(repoId: UUID, number: Int) -> Issue {
        Issue(id: UUID(), repoId: repoId, number: number, title: "Issue \(number)",
              authorLogin: "ghost", assignedToMe: false, assigneeLogins: [], labels: [],
              commentCount: 0, htmlUrl: URL(string: "https://github.com/o/r/issues/\(number)")!,
              updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func test_handle_noFilter_returnsAllIssuesAcrossRepos() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r1 = try await insertRepo(db, accountId: acct, name: "Alpha")
        let r2 = try await insertRepo(db, accountId: acct, name: "Bravo")
        try await db.issueCache.upsert([makeIssue(repoId: r1.id, number: 1)], for: r1.id)
        try await db.issueCache.upsert([makeIssue(repoId: r2.id, number: 2),
                                        makeIssue(repoId: r2.id, number: 3)], for: r2.id)

        let tool = ListIssuesTool(db: db)
        let result = try await tool.handle(params: nil)

        guard case .object(let obj) = result, case .array(let items) = obj["issues"] ?? .null else {
            return XCTFail("expected .object with .issues array, got \(result)")
        }
        XCTAssertEqual(items.count, 3)
    }

    func test_handle_unknownRepoId_returnsEmpty() async throws {
        let db = try makeDB()
        let tool = ListIssuesTool(db: db)
        let result = try await tool.handle(params: .object(["repo_id": .string(UUID().uuidString)]))
        guard case .object(let obj) = result, case .array(let items) = obj["issues"] ?? .null else {
            return XCTFail("expected .issues array")
        }
        XCTAssertTrue(items.isEmpty)
    }

    func test_isWrite_isFalse() throws {
        let db = try makeDB()
        let tool = ListIssuesTool(db: db)
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_list_issues")
    }
}
