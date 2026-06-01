import XCTest
import GRDB
@testable import Aerie

final class ListPRsToolTests: XCTestCase {
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

    private func insertRepo(_ db: AppDatabase, accountId: UUID, name: String) async throws -> Repository {
        let r = Repository(
            id: UUID(),
            name: name,
            localPath: URL(fileURLWithPath: "/tmp/\(name)"),
            githubOwner: "octocat",
            githubRepo: name.lowercased(),
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: 0,
            hidden: false
        )
        try await db.repos.insert(r)
        return r
    }

    private func makePR(repoId: UUID, number: Int) -> PullRequest {
        PullRequest(
            id: UUID(),
            repoId: repoId,
            number: number,
            title: "PR \(number)",
            authorLogin: "ghost",
            sourceBranch: "feat/x-\(number)",
            isMine: false,
            state: .open,
            ciState: .success,
            reviewState: .approved,
            labels: [],
            htmlUrl: URL(string: "https://github.com/octocat/repo/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Tests

    func test_handle_noFilter_returnsAllPRsAcrossRepos() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r1 = try await insertRepo(db, accountId: acct, name: "Alpha")
        let r2 = try await insertRepo(db, accountId: acct, name: "Bravo")
        let prs1 = [makePR(repoId: r1.id, number: 1), makePR(repoId: r1.id, number: 2)]
        let prs2 = [makePR(repoId: r2.id, number: 3), makePR(repoId: r2.id, number: 4)]
        try await db.prCache.upsert(prs1, for: r1.id)
        try await db.prCache.upsert(prs2, for: r2.id)

        let tool = ListPRsTool(db: db)
        let result = try await tool.handle(params: nil)

        guard case .object(let obj) = result,
              case .array(let items) = obj["prs"] ?? .null else {
            XCTFail("expected .object with .prs array, got \(result)")
            return
        }
        XCTAssertEqual(items.count, 4)
    }

    func test_handle_withRepoIdFilter_returnsOnlyThatRepo() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r1 = try await insertRepo(db, accountId: acct, name: "Alpha")
        let r2 = try await insertRepo(db, accountId: acct, name: "Bravo")
        let prs1 = [makePR(repoId: r1.id, number: 1), makePR(repoId: r1.id, number: 2)]
        let prs2 = [makePR(repoId: r2.id, number: 3), makePR(repoId: r2.id, number: 4)]
        try await db.prCache.upsert(prs1, for: r1.id)
        try await db.prCache.upsert(prs2, for: r2.id)

        let tool = ListPRsTool(db: db)
        let result = try await tool.handle(
            params: .object(["repo_id": .string(r1.id.uuidString)])
        )

        guard case .object(let obj) = result,
              case .array(let items) = obj["prs"] ?? .null else {
            XCTFail("expected .object with .prs array")
            return
        }
        XCTAssertEqual(items.count, 2)
    }

    func test_handle_unknownRepoId_returnsEmpty() async throws {
        let db = try makeDB()
        let tool = ListPRsTool(db: db)
        let result = try await tool.handle(
            params: .object(["repo_id": .string(UUID().uuidString)])
        )
        guard case .object(let obj) = result,
              case .array(let items) = obj["prs"] ?? .null else {
            XCTFail("expected .object with .prs array")
            return
        }
        XCTAssertTrue(items.isEmpty)
    }

    func test_isWrite_isFalse() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        let db = try! AppDatabase(url: url)
        let tool = ListPRsTool(db: db)
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_list_prs")
    }
}
