import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

// Minimal fake that returns no worktrees so snapshot tests stay stable.
private actor NoOpGitServiceForScreenTests: GitService {
    func worktrees(mainWorktreeAt url: URL) async -> [WorktreeRow] { [] }
    func removeWorktree(_ p: URL, mainWorktreeAt m: URL, force: Bool) async throws {}
    func readStatus(at url: URL, repoId: UUID) async throws -> LocalGitStatus { fatalError("unused") }
    func prLocalState(repoAt url: URL, prId: UUID, sourceBranch: String) async throws -> PRLocalState { fatalError("unused") }
    func hardResetToOrigin(repoAt url: URL, defaultBranch: String, token: String?) async throws -> HardResetSummary { fatalError("unused") }
    func updateBranchFromBase(repoAt url: URL, defaultBranch: String, token: String?) async throws { fatalError("unused") }
    func discardUnstaged(repoAt url: URL) async throws { fatalError("unused") }
    func forceCheckout(repoAt url: URL, branch: String, token: String?) async throws { fatalError("unused") }
}

/// Snapshot coverage for the full Repos screen at the main-window content size.
/// Seeds a temp DB with 3 repos covering the three card states
/// (clean-on-default, dirty-on-default, diverged), refreshes a real
/// `ReposViewModel`, then renders against the standard backdrop.
final class ReposScreenTests: XCTestCase {
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
    private func insertAccount(_ db: AppDatabase) throws -> UUID {
        let id = UUID()
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [id.uuidString, "carlos-li", "github.com"]
            )
        }
        return id
    }

    private func insertRepo(
        _ db: AppDatabase,
        id: UUID,
        accountId: UUID,
        name: String,
        repo: String,
        sortOrder: Int
    ) async throws -> Repository {
        let r = Repository(
            id: id,
            name: name,
            // Outside any user's $HOME so `RepoCard.collapsedPath` is stable.
            localPath: URL(fileURLWithPath: "/opt/repos/\(repo)"),
            githubOwner: "carlos-li",
            githubRepo: repo,
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: sortOrder,
            hidden: false
        )
        try await db.repos.insert(r)
        return r
    }

    func test_reposScreenSnapshot_threeRows() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)

        let aerieId  = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let bridgeId = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let cipherId = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!

        _ = try await insertRepo(db, id: aerieId,  accountId: acct, name: "Aerie",  repo: "aerie",  sortOrder: 0)
        _ = try await insertRepo(db, id: bridgeId, accountId: acct, name: "Bridge", repo: "bridge", sortOrder: 1)
        _ = try await insertRepo(db, id: cipherId, accountId: acct, name: "Cipher", repo: "cipher", sortOrder: 2)

        // Clean on default.
        try await db.gitStatusCache.upsert(LocalGitStatus(
            repoId: aerieId,
            currentBranch: "main",
            isDirty: false,
            dirtyFileCount: 0,
            aheadOfDefault: 0,
            behindOfDefault: 0,
            unpushedCommits: 0,
            originDefaultSha: "deadbeef",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        // Dirty on default.
        try await db.gitStatusCache.upsert(LocalGitStatus(
            repoId: bridgeId,
            currentBranch: "main",
            isDirty: true,
            dirtyFileCount: 3,
            aheadOfDefault: 0,
            behindOfDefault: 0,
            unpushedCommits: 0,
            originDefaultSha: "deadbeef",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        // Diverged — off default, ahead/behind, dirty.
        try await db.gitStatusCache.upsert(LocalGitStatus(
            repoId: cipherId,
            currentBranch: "feat/keychain-only",
            isDirty: true,
            dirtyFileCount: 2,
            aheadOfDefault: 3,
            behindOfDefault: 1,
            unpushedCommits: 0,
            originDefaultSha: "deadbeef",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let vm = ReposViewModel(db: db, gitService: NoOpGitServiceForScreenTests())
        await vm.refresh()

        // Sanity-check the VM landed in .ready before snapshotting.
        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.count, 3)

        let view = ZStack {
            Backdrop()
            ReposScreen(viewModel: vm, tabSelection: .constant(.repos))
        }
        .frame(width: 1240, height: 760)

        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 1240, height: 760)))
    }
}
