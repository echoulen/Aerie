import XCTest
import GRDB
@testable import Aerie

// MARK: - Test doubles

/// In-memory `PRFetching` that returns canned PRs per repo (or throws), and
/// records the (repoId, accountId) of every call so tests can assert the
/// orchestrator fetched with the repo's *bound* account.
actor StubPRFetcher: PRFetching {
    private var resultsByRepo: [UUID: [PullRequest]] = [:]
    private var error: Error?
    private(set) var calls: [(repoId: UUID, accountId: UUID)] = []

    func setResult(_ prs: [PullRequest], forRepo repoId: UUID) {
        resultsByRepo[repoId] = prs
    }

    func setError(_ e: Error) { error = e }

    func callCount() -> Int { calls.count }
    func accountIds() -> [UUID] { calls.map(\.accountId) }

    func listOpenPRs(
        owner: String,
        repo: String,
        repoId: UUID,
        accountId: UUID
    ) async throws -> MultiAccountAPIResult<[PullRequest]> {
        calls.append((repoId, accountId))
        if let error { throw error }
        return MultiAccountAPIResult(value: resultsByRepo[repoId] ?? [], successfulAccountId: accountId)
    }
}

/// Counts how many times the `onChange` hook fired.
actor ChangeCounter {
    private(set) var count = 0
    func bump() { count += 1 }
    func value() -> Int { count }
}

// MARK: - Tests

final class PRSyncServiceTests: XCTestCase {
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

    /// Run a command via `/usr/bin/env`, capturing combined stdout+stderr.
    /// Throws on non-zero exit. Mirrors `GitStatusRefresherTests.shell`.
    @discardableResult
    private func shell(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(
                domain: "shell", code: Int(p.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: out]
            )
        }
        return out
    }

    /// Fresh temp git repo with one commit on `main`. Returns its working tree.
    private func makeTempRepo() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        tempURLs.append(url)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        try shell(["git", "-C", url.path, "init", "-q", "-b", "main"])
        try "hi".write(
            to: url.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )
        try shell(["git", "-C", url.path, "add", "."])
        try shell([
            "git", "-C", url.path,
            "-c", "user.email=t@t", "-c", "user.name=T",
            "commit", "-q", "-m", "init",
        ])
        return url
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
        hidden: Bool = false,
        localPath: URL? = nil
    ) async throws -> Repository {
        let r = Repository(
            id: UUID(),
            name: name,
            localPath: localPath ?? URL(fileURLWithPath: "/tmp/\(name)"),
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

    private func makePR(repoId: UUID, number: Int, sourceBranch: String? = nil) -> PullRequest {
        PullRequest(
            id: UUID(),
            repoId: repoId,
            number: number,
            title: "PR \(number)",
            authorLogin: "ghost",
            sourceBranch: sourceBranch ?? "feat/x-\(number)",
            isMine: false,
            state: .open,
            ciState: .success,
            reviewState: .approved,
            labels: [],
            htmlUrl: URL(string: "https://github.com/octocat/hello-world/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: sync(repoId:)

    func test_sync_fetchesWithBoundAccount_upsertsCache_andNotifies() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)

        let fetcher = StubPRFetcher()
        await fetcher.setResult([makePR(repoId: repo.id, number: 1), makePR(repoId: repo.id, number: 2)], forRepo: repo.id)
        let counter = ChangeCounter()

        let service = PRSyncService(db: db, api: fetcher, git: LiveGitService(), onChange: { await counter.bump() })
        await service.sync(repoId: repo.id)

        // Cache now holds the fetched PRs.
        let cached = try await db.prCache.prs(forRepo: repo.id)
        XCTAssertEqual(cached.map(\.number).sorted(), [1, 2])

        // Fetched with the repo's bound account (primaryAccountId).
        let accountIds = await fetcher.accountIds()
        XCTAssertEqual(accountIds, [acct])

        // Notified exactly once.
        let changes = await counter.value()
        XCTAssertEqual(changes, 1)
    }

    func test_sync_computesAndCachesLocalState_forCheckedOutBranch() async throws {
        // Repo checked out on the PR's source branch, with a dirty working tree.
        let repoURL = try makeTempRepo()
        try shell(["git", "-C", repoURL.path, "checkout", "-q", "-b", "feat/local"])
        try "hi\nmore".write(
            to: repoURL.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )

        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct, localPath: repoURL)

        let pr = makePR(repoId: repo.id, number: 1, sourceBranch: "feat/local")
        let fetcher = StubPRFetcher()
        await fetcher.setResult([pr], forRepo: repo.id)

        let service = PRSyncService(db: db, api: fetcher, git: LiveGitService())
        await service.sync(repoId: repo.id)

        // The sync should have resolved the branch's local state and cached it,
        // so the PRs tab can render dirty/ahead/behind instead of a permanent
        // muted "Not checked out locally".
        let local = try await db.prLocalStateCache.state(forPr: pr.id)
        let state = try XCTUnwrap(local, "sync should compute and cache the PR's local state")
        XCTAssertTrue(state.localBranchExists)
        XCTAssertTrue(state.isCurrentBranch)
        XCTAssertEqual(state.dirty, true)
    }

    func test_sync_localBranchExistsButNotCheckedOut_reportsExistenceOnly() async throws {
        // The PR's source branch exists locally but isn't checked out. Per
        // GitService's contract we report only existence — dirty/ahead/behind
        // stay nil because computing them would need a (destructive) worktree
        // switch. This pins that documented behavior end-to-end through sync.
        let repoURL = try makeTempRepo()
        try shell(["git", "-C", repoURL.path, "branch", "feat/other"]) // create, don't switch

        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct, localPath: repoURL)

        let pr = makePR(repoId: repo.id, number: 1, sourceBranch: "feat/other")
        let fetcher = StubPRFetcher()
        await fetcher.setResult([pr], forRepo: repo.id)

        let service = PRSyncService(db: db, api: fetcher, git: LiveGitService())
        await service.sync(repoId: repo.id)

        let cached = try await db.prLocalStateCache.state(forPr: pr.id)
        let state = try XCTUnwrap(cached)
        XCTAssertTrue(state.localBranchExists)
        XCTAssertFalse(state.isCurrentBranch)
        XCTAssertNil(state.dirty)
        XCTAssertNil(state.ahead)
        XCTAssertNil(state.behind)
    }

    func test_sync_unknownRepoId_isNoOp() async throws {
        let db = try makeDB()
        let fetcher = StubPRFetcher()
        let counter = ChangeCounter()

        let service = PRSyncService(db: db, api: fetcher, git: LiveGitService(), onChange: { await counter.bump() })
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

        // Seed the cache with a known PR so we can detect any clobbering.
        let existing = makePR(repoId: repo.id, number: 7)
        try await db.prCache.upsert([existing], for: repo.id)

        let fetcher = StubPRFetcher()
        await fetcher.setError(URLError(.notConnectedToInternet))
        let counter = ChangeCounter()

        let service = PRSyncService(db: db, api: fetcher, git: LiveGitService(), onChange: { await counter.bump() })
        await service.sync(repoId: repo.id)   // must not throw

        // A failed fetch must never wipe the previously-cached PRs.
        let cached = try await db.prCache.prs(forRepo: repo.id)
        XCTAssertEqual(cached.map(\.number), [7])
        let changes = await counter.value()
        XCTAssertEqual(changes, 0, "no successful sync → no notification")
    }

    func test_sync_apiSyncDisabled_isNoOp() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct)
        try await db.repos.setApiSyncDisabled(id: repo.id, true)

        let fetcher = StubPRFetcher()
        await fetcher.setResult([makePR(repoId: repo.id, number: 1)], forRepo: repo.id)
        let counter = ChangeCounter()

        let service = PRSyncService(db: db, api: fetcher, git: LiveGitService(), onChange: { await counter.bump() })
        await service.sync(repoId: repo.id)

        let count = await fetcher.callCount()
        XCTAssertEqual(count, 0, "api-sync-disabled repo → no fetch")
        let cached = try await db.prCache.prs(forRepo: repo.id)
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

        let fetcher = StubPRFetcher()
        await fetcher.setResult([makePR(repoId: visible.id, number: 1)], forRepo: visible.id)
        await fetcher.setResult([makePR(repoId: hidden.id, number: 2)], forRepo: hidden.id)
        let counter = ChangeCounter()

        let service = PRSyncService(db: db, api: fetcher, git: LiveGitService(), onChange: { await counter.bump() })
        await service.syncAll()

        let visibleCached = try await db.prCache.prs(forRepo: visible.id)
        XCTAssertEqual(visibleCached.map(\.number), [1])
        let hiddenCached = try await db.prCache.prs(forRepo: hidden.id)
        XCTAssertEqual(hiddenCached, [], "hidden repos are not synced")
        let count = await fetcher.callCount()
        XCTAssertEqual(count, 1, "only the visible repo is fetched")
    }
}
