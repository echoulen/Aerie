import XCTest
import GRDB
@testable import Aerie

final class ListMergedBranchesToolTests: XCTestCase {
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
    private func makeMerged(repoId: UUID, branch: String, number: Int) -> MergedBranchInfo {
        MergedBranchInfo(repoId: repoId, branch: branch, prNumber: number,
                         prUrl: URL(string: "https://github.com/o/r/pull/\(number)")!,
                         headOid: "abc123", mergedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func test_handle_noFilter_returnsAllMergedBranches() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r1 = try await insertRepo(db, accountId: acct, name: "Alpha")
        let r2 = try await insertRepo(db, accountId: acct, name: "Bravo")
        try await db.mergedBranchCache.upsert(makeMerged(repoId: r1.id, branch: "feat/a", number: 1))
        try await db.mergedBranchCache.upsert(makeMerged(repoId: r2.id, branch: "feat/b", number: 2))

        let tool = ListMergedBranchesTool(db: db)
        let result = try await tool.handle(params: nil)

        guard case .object(let obj) = result, case .array(let items) = obj["merged_branches"] ?? .null else {
            return XCTFail("expected .merged_branches array, got \(result)")
        }
        XCTAssertEqual(items.count, 2)
    }

    func test_handle_repoWithNoMergedBranch_returnsEmpty() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let r1 = try await insertRepo(db, accountId: acct, name: "Alpha")
        let tool = ListMergedBranchesTool(db: db)
        let result = try await tool.handle(params: .object(["repo_id": .string(r1.id.uuidString)]))
        guard case .object(let obj) = result, case .array(let items) = obj["merged_branches"] ?? .null else {
            return XCTFail("expected .merged_branches array")
        }
        XCTAssertTrue(items.isEmpty)
    }

    func test_isWrite_isFalse() throws {
        let db = try makeDB()
        let tool = ListMergedBranchesTool(db: db)
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_list_merged_branches")
    }
}
