import XCTest
import GRDB
@testable import Aerie

// Minimal fake that returns no worktrees — lets existing tests stay focused
// on repo/status projection without touching the git layer.
private actor NoOpGitService: GitService {
    func worktrees(mainWorktreeAt url: URL) async -> [WorktreeRow] { [] }
    func removeWorktree(_ p: URL, mainWorktreeAt m: URL, force: Bool) async throws {}
    func readStatus(at url: URL, repoId: UUID) async throws -> LocalGitStatus { fatalError("unused") }
    func prLocalState(repoAt url: URL, prId: UUID, sourceBranch: String) async throws -> PRLocalState { fatalError("unused") }
    func hardResetToOrigin(repoAt url: URL, defaultBranch: String, token: String?) async throws -> HardResetSummary { fatalError("unused") }
    func updateBranchFromBase(repoAt url: URL, defaultBranch: String, token: String?) async throws { fatalError("unused") }
    func discardUnstaged(repoAt url: URL) async throws { fatalError("unused") }
    func forceCheckout(repoAt url: URL, branch: String, token: String?) async throws { fatalError("unused") }
    func deleteLocalBranch(repoAt url: URL, branch: String) async throws { fatalError("unused") }
}

final class ReposViewModelTests: XCTestCase {
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
        sortOrder: Int = 0,
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
            sortOrder: sortOrder,
            hidden: hidden
        )
        try await db.repos.insert(r)
        return r
    }

    private func makeStatus(
        repoId: UUID,
        currentBranch: String = "main",
        isDirty: Bool = false,
        dirtyFileCount: Int = 0,
        ahead: Int = 0,
        behind: Int = 0,
        unpushed: Int = 0
    ) -> LocalGitStatus {
        LocalGitStatus(
            repoId: repoId,
            currentBranch: currentBranch,
            isDirty: isDirty,
            dirtyFileCount: dirtyFileCount,
            aheadOfDefault: ahead,
            behindOfDefault: behind,
            unpushedCommits: unpushed,
            originDefaultSha: "deadbeef",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Tests

    func test_refresh_emitsReady_orderedBySortOrder() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)

        // Insert in scrambled order to prove the DAO ordering survives the VM.
        let two   = try await insertRepo(db, accountId: acct, name: "Charlie", repo: "charlie", sortOrder: 2)
        let zero  = try await insertRepo(db, accountId: acct, name: "Alpha",   repo: "alpha",   sortOrder: 0)
        let one   = try await insertRepo(db, accountId: acct, name: "Bravo",   repo: "bravo",   sortOrder: 1)

        let vm = ReposViewModel(db: db, gitService: NoOpGitService())
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map { $0.repo.id }, [zero.id, one.id, two.id])
    }

    func test_refresh_emitsEmpty_whenNoRepos() async throws {
        let db = try makeDB()
        let vm = ReposViewModel(db: db, gitService: NoOpGitService())
        await vm.refresh()
        XCTAssertEqual(vm.state, .empty)
    }

    func test_refresh_attachesStatus_whenAvailable() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct, name: "WithStatus")
        let bare = try await insertRepo(db, accountId: acct, name: "NoStatus", repo: "nostatus", sortOrder: 1)

        let status = makeStatus(
            repoId: repo.id,
            currentBranch: "feat/x",
            isDirty: true,
            dirtyFileCount: 3,
            ahead: 2,
            behind: 1,
            unpushed: 0
        )
        try await db.gitStatusCache.upsert(status)

        let vm = ReposViewModel(db: db, gitService: NoOpGitService())
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.count, 2)
        // First repo (sortOrder 0) has status.
        XCTAssertEqual(rows[0].repo.id, repo.id)
        XCTAssertEqual(rows[0].status, status)
        // Second repo (sortOrder 1) has no cached status.
        XCTAssertEqual(rows[1].repo.id, bare.id)
        XCTAssertNil(rows[1].status)
    }

    func test_refresh_excludesHiddenRepos() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let visible = try await insertRepo(db, accountId: acct, name: "Visible")
        _ = try await insertRepo(db, accountId: acct, name: "Hidden", repo: "hidden", sortOrder: 1, hidden: true)

        let vm = ReposViewModel(db: db, gitService: NoOpGitService())
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].repo.id, visible.id)
    }
}
