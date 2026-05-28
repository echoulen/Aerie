import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the full PRs screen at the main-window content size.
/// Seeds a temp DB with 3 PRs across 2 repos, refreshes a real `PRsViewModel`,
/// then renders the screen against the standard backdrop.
final class PRsScreenTests: XCTestCase {
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

    private func insertRepo(_ db: AppDatabase, accountId: UUID, name: String, repo: String) async throws -> Repository {
        let r = Repository(
            id: UUID(),
            name: name,
            localPath: URL(fileURLWithPath: "/tmp/\(name)"),
            githubOwner: "carlos-li",
            githubRepo: repo,
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: 0,
            hidden: false
        )
        try await db.repos.insert(r)
        return r
    }

    func test_prsScreenSnapshot_threeRows() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let aerie = try await insertRepo(db, accountId: acct, name: "Aerie", repo: "aerie")
        let bridge = try await insertRepo(db, accountId: acct, name: "Bridge", repo: "bridge")

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let pr1 = PullRequest(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            repoId: aerie.id, number: 142,
            title: "Wire PRCard local strip and ready-to-ship eyebrow",
            authorLogin: "carlos-li", sourceBranch: "feat/phase9-prs-view",
            isMine: true, state: .open, ciState: .success, reviewState: .approved,
            labels: ["enhancement"],
            htmlUrl: URL(string: "https://github.com/carlos-li/aerie/pull/142")!,
            updatedAt: base.addingTimeInterval(300)
        )
        let pr2 = PullRequest(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            repoId: aerie.id, number: 138,
            title: "PollingScheduler hooks into AppFocusObserver for foreground/background gating",
            authorLogin: "another-dev", sourceBranch: "feat/polling-pause",
            isMine: false, state: .open, ciState: .pending, reviewState: .reviewRequired,
            labels: [],
            htmlUrl: URL(string: "https://github.com/carlos-li/aerie/pull/138")!,
            updatedAt: base.addingTimeInterval(200)
        )
        let pr3 = PullRequest(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            repoId: bridge.id, number: 17,
            title: "Switch token store to Keychain-only and drop env-var fallback",
            authorLogin: "carlos-li", sourceBranch: "fix/keychain-only",
            isMine: true, state: .open, ciState: .failure, reviewState: .changesRequested,
            labels: [],
            htmlUrl: URL(string: "https://github.com/carlos-li/bridge/pull/17")!,
            updatedAt: base.addingTimeInterval(100)
        )

        try await db.prCache.upsert([pr1, pr2], for: aerie.id)
        try await db.prCache.upsert([pr3], for: bridge.id)

        try await db.prLocalStateCache.upsert(
            PRLocalState(
                prId: pr1.id, sourceBranch: pr1.sourceBranch,
                localBranchExists: true, isCurrentBranch: true,
                dirty: false, ahead: 2, behind: 0, unpushed: 1
            ),
            repoId: aerie.id
        )
        try await db.prLocalStateCache.upsert(
            PRLocalState(
                prId: pr3.id, sourceBranch: pr3.sourceBranch,
                localBranchExists: true, isCurrentBranch: false,
                dirty: nil, ahead: nil, behind: nil, unpushed: nil
            ),
            repoId: bridge.id
        )

        let vm = PRsViewModel(db: db)
        await vm.refresh()

        // Sanity: confirm the VM landed in .ready before rendering.
        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.count, 3)

        // Pin "now" so the "updated x ago" string stays stable across runs.
        let fixedNow = Date(timeIntervalSince1970: 1_700_010_000)
        let view = ZStack {
            Backdrop()
            PRsScreen(viewModel: vm, now: fixedNow)
        }
        .frame(width: 1240, height: 760)

        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 1240, height: 760)))
    }
}
