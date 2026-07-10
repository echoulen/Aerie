import XCTest
import GRDB
@testable import Aerie

/// In-memory `MergedBranchFetching` returning a canned ref per head branch and
/// recording each call's (headBranch, accountId).
actor StubMergedFetcher: MergedBranchFetching {
    private var refByBranch: [String: MergedPRRef] = [:]
    private(set) var calls: [(headBranch: String, accountId: UUID)] = []

    func setRef(_ ref: MergedPRRef, forBranch branch: String) { refByBranch[branch] = ref }
    func callCount() -> Int { calls.count }
    func accountIds() -> [UUID] { calls.map(\.accountId) }

    func mergedPR(owner: String, repo: String, headBranch: String, accountId: UUID)
        async throws -> MultiAccountAPIResult<MergedPRRef?> {
        calls.append((headBranch, accountId))
        return MultiAccountAPIResult(value: refByBranch[headBranch], successfulAccountId: accountId)
    }
}

final class MergedBranchSyncTests: XCTestCase {
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
            localPath: URL(fileURLWithPath: "/tmp/example"),
            githubOwner: "octocat", githubRepo: "hello-world",
            defaultBranch: "main", primaryAccountId: accountId,
            sortOrder: 0, hidden: false
        )
        try await db.repos.insert(r)
        return r
    }
    private func upsertStatus(_ db: AppDatabase, repoId: UUID, branch: String) async throws {
        try await db.gitStatusCache.upsert(LocalGitStatus(
            repoId: repoId, currentBranch: branch, isDirty: false, dirtyFileCount: 0,
            aheadOfDefault: 0, behindOfDefault: 0, unpushedCommits: 0,
            originDefaultSha: "abc1234", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)))
    }
    private func ref(_ n: Int) -> MergedPRRef {
        MergedPRRef(
            number: n,
            url: URL(string: "https://github.com/octocat/hello-world/pull/\(n)")!,
            headOid: "abc1234", mergedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func test_offDefault_withMergedPR_writesCacheWithBoundAccount() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await upsertStatus(db, repoId: repo.id, branch: "IOE-3017")

        let fetcher = StubMergedFetcher()
        await fetcher.setRef(ref(62), forBranch: "IOE-3017")

        let sync = MergedBranchSync(db: db, api: fetcher)
        await sync.sync(repoId: repo.id)

        let info = try await db.mergedBranchCache.info(forRepo: repo.id)
        XCTAssertEqual(info?.prNumber, 62)
        XCTAssertEqual(info?.branch, "IOE-3017")
        let accountIds = await fetcher.accountIds()
        XCTAssertEqual(accountIds, [acct])
    }

    func test_onDefault_skipsFetchAndClearsCache() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        // Seed a stale entry, then go back on default.
        try await db.mergedBranchCache.upsert(MergedBranchInfo(
            repoId: repo.id, branch: "IOE-3017", prNumber: 62,
            prUrl: URL(string: "https://github.com/octocat/hello-world/pull/62")!,
            headOid: "abc1234", mergedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        try await upsertStatus(db, repoId: repo.id, branch: "main") // == defaultBranch

        let fetcher = StubMergedFetcher()
        let sync = MergedBranchSync(db: db, api: fetcher)
        await sync.sync(repoId: repo.id)

        let callCount1 = await fetcher.callCount()
        XCTAssertEqual(callCount1, 0, "on default → no API call")
        let info = try await db.mergedBranchCache.info(forRepo: repo.id)
        XCTAssertNil(info, "stale entry cleared")
    }

    func test_offDefault_noMergedPR_clearsCache() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.mergedBranchCache.upsert(MergedBranchInfo(
            repoId: repo.id, branch: "IOE-3017", prNumber: 62,
            prUrl: URL(string: "https://github.com/octocat/hello-world/pull/62")!,
            headOid: "abc1234", mergedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        try await upsertStatus(db, repoId: repo.id, branch: "IOE-9999") // off-default, but no PR

        let fetcher = StubMergedFetcher() // returns nil for any branch
        let sync = MergedBranchSync(db: db, api: fetcher)
        await sync.sync(repoId: repo.id)

        let info = try await db.mergedBranchCache.info(forRepo: repo.id)
        XCTAssertNil(info)
    }

    func test_apiSyncDisabled_skipsFetchAndLeavesCacheUntouched() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.repos.setApiSyncDisabled(id: repo.id, true)
        try await upsertStatus(db, repoId: repo.id, branch: "IOE-3017")
        // Seed a stale cache entry — disabling must not touch it either way.
        try await db.mergedBranchCache.upsert(MergedBranchInfo(
            repoId: repo.id, branch: "IOE-3017", prNumber: 62,
            prUrl: URL(string: "https://github.com/octocat/hello-world/pull/62")!,
            headOid: "abc1234", mergedAt: Date(timeIntervalSince1970: 1_700_000_000)))

        let fetcher = StubMergedFetcher()
        await fetcher.setRef(ref(99), forBranch: "IOE-3017")

        let sync = MergedBranchSync(db: db, api: fetcher)
        await sync.sync(repoId: repo.id)

        let callCount = await fetcher.callCount()
        XCTAssertEqual(callCount, 0, "api-sync-disabled repo → no fetch")
        let info = try await db.mergedBranchCache.info(forRepo: repo.id)
        XCTAssertEqual(info?.prNumber, 62, "stale entry left untouched, not cleared")
    }

    func test_unknownRepo_isNoOp() async throws {
        let db = try makeDB()
        let fetcher = StubMergedFetcher()
        let sync = MergedBranchSync(db: db, api: fetcher)
        await sync.sync(repoId: UUID()) // must not throw
        let callCount2 = await fetcher.callCount()
        XCTAssertEqual(callCount2, 0)
    }
}
