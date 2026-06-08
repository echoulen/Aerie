import XCTest
@testable import Aerie

private actor FakeGitService: GitService {
    let canned: [WorktreeRow]
    init(_ canned: [WorktreeRow]) { self.canned = canned }

    func worktrees(mainWorktreeAt url: URL) async -> [WorktreeRow] { canned }
    func removeWorktree(_ p: URL, mainWorktreeAt m: URL, force: Bool) async throws {}

    func readStatus(at url: URL, repoId: UUID) async throws -> LocalGitStatus { fatalError("unused") }
    func prLocalState(repoAt url: URL, prId: UUID, sourceBranch: String) async throws -> PRLocalState { fatalError("unused") }
    func hardResetToOrigin(repoAt url: URL, defaultBranch: String, token: String?) async throws -> HardResetSummary { fatalError("unused") }
    func updateBranchFromBase(repoAt url: URL, defaultBranch: String, token: String?) async throws { fatalError("unused") }
    func discardUnstaged(repoAt url: URL) async throws { fatalError("unused") }
    func forceCheckout(repoAt url: URL, branch: String, token: String?) async throws { fatalError("unused") }
    func deleteLocalBranch(repoAt url: URL, branch: String) async throws { fatalError("unused") }
}

@MainActor
final class ReposViewModelWorktreeTests: XCTestCase {

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
        name: String = "Example"
    ) async throws -> Repository {
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

    func testRefreshProjectsLiveWorktreesOntoRows() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        _ = try await insertRepo(db, accountId: acct, name: "Example")

        let wt = WorktreeRow(
            path: URL(fileURLWithPath: "/tmp/wt/feature"),
            branchLabel: "feature", isDetached: false,
            isDirty: true, dirtyFileCount: 2, prunable: false)
        let vm = ReposViewModel(db: db, gitService: FakeGitService([wt]))

        await vm.refresh()

        guard case let .ready(rows) = vm.state, let row = rows.first else {
            return XCTFail("expected ready state with one row, got \(vm.state)")
        }
        XCTAssertEqual(row.worktrees, [wt])
    }
}
