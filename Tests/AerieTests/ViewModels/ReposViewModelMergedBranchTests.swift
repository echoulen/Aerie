import XCTest
import GRDB
@testable import Aerie

final class ReposViewModelMergedBranchTests: XCTestCase {
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
    private func insertAccount(_ db: AppDatabase, id: UUID = UUID()) throws -> UUID {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [id.uuidString, "tester", "github.com"]
            )
        }
        return id
    }
    private func insertRepo(_ db: AppDatabase, accountId: UUID) async throws -> Repository {
        let r = Repository(
            id: UUID(), name: "Example",
            localPath: URL(fileURLWithPath: "/tmp/example-\(UUID().uuidString)"),
            githubOwner: "octocat", githubRepo: "hello-world",
            defaultBranch: "main", primaryAccountId: accountId,
            sortOrder: 0, hidden: false
        )
        try await db.repos.insert(r)
        return r
    }

    func test_refresh_projectsMergedBranchFromCache() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)

        try await db.gitStatusCache.upsert(LocalGitStatus(
            repoId: repo.id, currentBranch: "IOE-3017", isDirty: false, dirtyFileCount: 0,
            aheadOfDefault: 0, behindOfDefault: 0, unpushedCommits: 0,
            originDefaultSha: "abc1234", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        try await db.mergedBranchCache.upsert(MergedBranchInfo(
            repoId: repo.id, branch: "IOE-3017", prNumber: 62,
            prUrl: URL(string: "https://github.com/octocat/hello-world/pull/62")!,
            headOid: "abc1234", mergedAt: Date(timeIntervalSince1970: 1_700_000_000)))

        let vm = ReposViewModel(db: db, gitService: LiveGitService())
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            return XCTFail("expected .ready, got \(vm.state)")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].mergedBranch?.prNumber, 62)
        XCTAssertEqual(rows[0].mergedBranch?.branch, "IOE-3017")
    }

    func test_refresh_mergedBranchNilWhenNoCacheEntry() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.gitStatusCache.upsert(LocalGitStatus(
            repoId: repo.id, currentBranch: "main", isDirty: false, dirtyFileCount: 0,
            aheadOfDefault: 0, behindOfDefault: 0, unpushedCommits: 0,
            originDefaultSha: "abc1234", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)))

        let vm = ReposViewModel(db: db, gitService: LiveGitService())
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            return XCTFail("expected .ready, got \(vm.state)")
        }
        XCTAssertNil(rows[0].mergedBranch)
    }
}
