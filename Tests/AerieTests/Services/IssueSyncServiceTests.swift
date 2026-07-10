import XCTest
import GRDB
@testable import Aerie

// MARK: - Test doubles

/// In-memory `IssueFetching` that returns canned issues per repo (or throws),
/// and records the (repoId, accountId) of every call so tests can assert the
/// orchestrator fetched with the repo's *bound* account. Mirrors `StubPRFetcher`.
actor StubIssueFetcher: IssueFetching {
    private var resultsByRepo: [UUID: [Issue]] = [:]
    private var error: Error?
    private(set) var calls: [(repoId: UUID, accountId: UUID)] = []

    func setResult(_ issues: [Issue], forRepo repoId: UUID) {
        resultsByRepo[repoId] = issues
    }

    func setError(_ e: Error) { error = e }

    func callCount() -> Int { calls.count }
    func accountIds() -> [UUID] { calls.map(\.accountId) }

    func listOpenIssues(
        owner: String,
        repo: String,
        repoId: UUID,
        accountId: UUID
    ) async throws -> MultiAccountAPIResult<[Issue]> {
        calls.append((repoId, accountId))
        if let error { throw error }
        return MultiAccountAPIResult(value: resultsByRepo[repoId] ?? [], successfulAccountId: accountId)
    }
}

// MARK: - Tests

final class IssueSyncServiceTests: XCTestCase {
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
        assigneeLogins: [String] = []
    ) -> Issue {
        Issue(
            id: UUID(),
            repoId: repoId,
            number: number,
            title: "Issue \(number)",
            authorLogin: "ghost",
            // Provisional false — the sync service is expected to re-resolve it.
            assignedToMe: false,
            assigneeLogins: assigneeLogins,
            labels: [],
            commentCount: 0,
            htmlUrl: URL(string: "https://github.com/octocat/hello-world/issues/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: sync(repoId:)

    func test_sync_fetchesWithBoundAccount_upsertsCache_andNotifies() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)

        let fetcher = StubIssueFetcher()
        await fetcher.setResult([makeIssue(repoId: repo.id, number: 1), makeIssue(repoId: repo.id, number: 2)], forRepo: repo.id)
        let counter = ChangeCounter()

        let service = IssueSyncService(db: db, api: fetcher, onChange: { await counter.bump() })
        await service.sync(repoId: repo.id)

        let cached = try await db.issueCache.issues(forRepo: repo.id)
        XCTAssertEqual(cached.map(\.number).sorted(), [1, 2])

        let accountIds = await fetcher.accountIds()
        XCTAssertEqual(accountIds, [acct])

        let changes = await counter.value()
        XCTAssertEqual(changes, 1)
    }

    func test_sync_unknownRepoId_isNoOp() async throws {
        let db = try makeDB()
        let fetcher = StubIssueFetcher()
        let counter = ChangeCounter()

        let service = IssueSyncService(db: db, api: fetcher, onChange: { await counter.bump() })
        await service.sync(repoId: UUID())

        let count = await fetcher.callCount()
        XCTAssertEqual(count, 0, "no repo → no fetch")
        let changes = await counter.value()
        XCTAssertEqual(changes, 0, "no repo → no notification")
    }

    func test_sync_fetchThrows_leavesCacheUntouched_andDoesNotNotify() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)

        let existing = makeIssue(repoId: repo.id, number: 7)
        try await db.issueCache.upsert([existing], for: repo.id)

        let fetcher = StubIssueFetcher()
        await fetcher.setError(URLError(.notConnectedToInternet))
        let counter = ChangeCounter()

        let service = IssueSyncService(db: db, api: fetcher, onChange: { await counter.bump() })
        await service.sync(repoId: repo.id)   // must not throw

        let cached = try await db.issueCache.issues(forRepo: repo.id)
        XCTAssertEqual(cached.map(\.number), [7])
        let changes = await counter.value()
        XCTAssertEqual(changes, 0, "no successful sync → no notification")
    }

    func test_sync_resolvesAssignedToMe_acrossAllConnectedAccounts() async throws {
        let db = try makeDB()
        // Repo is synced via the "bot" account…
        let bot = try insertAccount(db, login: "bot-account")
        // …but the user also has their personal account connected.
        _ = try insertAccount(db, login: "echoulen")
        let repo = try await insertRepo(db, accountId: bot)

        let fetcher = StubIssueFetcher()
        await fetcher.setResult(
            [
                // Assigned to the personal account (NOT the syncing account).
                makeIssue(repoId: repo.id, number: 1, assigneeLogins: ["echoulen"]),
                // Assigned to a stranger.
                makeIssue(repoId: repo.id, number: 2, assigneeLogins: ["someone-else"]),
                // Unassigned.
                makeIssue(repoId: repo.id, number: 3, assigneeLogins: []),
            ],
            forRepo: repo.id
        )

        let service = IssueSyncService(db: db, api: fetcher)
        await service.sync(repoId: repo.id)

        let cached = try await db.issueCache.issues(forRepo: repo.id)
        let byNumber = Dictionary(uniqueKeysWithValues: cached.map { ($0.number, $0) })
        XCTAssertEqual(byNumber[1]?.assignedToMe, true, "assigned to a connected (non-syncing) account → yours")
        XCTAssertEqual(byNumber[2]?.assignedToMe, false, "assigned to a stranger → not yours")
        XCTAssertEqual(byNumber[3]?.assignedToMe, false, "unassigned → not yours")
    }

    func test_sync_resolvesAssignedToMe_caseInsensitively() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db, login: "Echoulen")
        let repo = try await insertRepo(db, accountId: acct)

        let fetcher = StubIssueFetcher()
        await fetcher.setResult(
            [makeIssue(repoId: repo.id, number: 1, assigneeLogins: ["echoulen"])],
            forRepo: repo.id
        )

        let service = IssueSyncService(db: db, api: fetcher)
        await service.sync(repoId: repo.id)

        let cached = try await db.issueCache.issues(forRepo: repo.id)
        XCTAssertEqual(cached.first?.assignedToMe, true, "login match is case-insensitive")
    }

    func test_sync_apiSyncDisabled_isNoOp() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.repos.setApiSyncDisabled(id: repo.id, true)

        let fetcher = StubIssueFetcher()
        await fetcher.setResult([makeIssue(repoId: repo.id, number: 1)], forRepo: repo.id)
        let counter = ChangeCounter()

        let service = IssueSyncService(db: db, api: fetcher, onChange: { await counter.bump() })
        await service.sync(repoId: repo.id)

        let count = await fetcher.callCount()
        XCTAssertEqual(count, 0, "api-sync-disabled repo → no fetch")
        let cached = try await db.issueCache.issues(forRepo: repo.id)
        XCTAssertEqual(cached, [], "no fetch → cache stays empty")
        let changes = await counter.value()
        XCTAssertEqual(changes, 0, "no fetch → no notification")
    }

    // MARK: syncAll()

    func test_syncAll_syncsVisibleRepos_skipsHidden() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let visible = try await insertRepo(db, accountId: acct, name: "Visible", repo: "visible")
        let hidden = try await insertRepo(db, accountId: acct, name: "Hidden", repo: "hidden", hidden: true)

        let fetcher = StubIssueFetcher()
        await fetcher.setResult([makeIssue(repoId: visible.id, number: 1)], forRepo: visible.id)
        await fetcher.setResult([makeIssue(repoId: hidden.id, number: 2)], forRepo: hidden.id)
        let counter = ChangeCounter()

        let service = IssueSyncService(db: db, api: fetcher, onChange: { await counter.bump() })
        await service.syncAll()

        let visibleCached = try await db.issueCache.issues(forRepo: visible.id)
        XCTAssertEqual(visibleCached.map(\.number), [1])
        let hiddenCached = try await db.issueCache.issues(forRepo: hidden.id)
        XCTAssertEqual(hiddenCached, [], "hidden repos are not synced")
        let count = await fetcher.callCount()
        XCTAssertEqual(count, 1, "only the visible repo is fetched")
    }
}
