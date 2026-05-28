import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the full Repositories screen at the Settings
/// content size. Seeds a temp DB with 2 accounts + 3 repos, refreshes a
/// real `RepositoriesViewModel`, then snapshots the rendered view.
final class RepositoriesScreenTests: XCTestCase {
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
    private func insertAccount(
        _ db: AppDatabase,
        id: UUID,
        login: String,
        host: String = "github.com"
    ) throws -> GitHubAccount {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [id.uuidString, login, host]
            )
        }
        return GitHubAccount(id: id, login: login, host: host)
    }

    private func insertRepo(
        _ db: AppDatabase,
        id: UUID,
        accountId: UUID,
        name: String,
        owner: String = "carlos-li",
        repo: String,
        sortOrder: Int,
        defaultBranch: String = "main",
        localPath: URL = URL(fileURLWithPath: "/opt/repos")
    ) async throws {
        let r = Repository(
            id: id,
            name: name,
            localPath: localPath.appendingPathComponent(name.lowercased()),
            githubOwner: owner,
            githubRepo: repo,
            defaultBranch: defaultBranch,
            primaryAccountId: accountId,
            sortOrder: sortOrder,
            hidden: false
        )
        try await db.repos.insert(r)
    }

    func test_repositoriesScreen_threeReposTwoAccounts() async throws {
        let db = try makeDB()

        let primaryId   = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!
        let secondaryId = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000002")!
        _ = try insertAccount(db, id: primaryId,   login: "carlos-li")
        _ = try insertAccount(db, id: secondaryId, login: "cli-work")

        try await insertRepo(
            db,
            id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!,
            accountId: primaryId,
            name: "Aerie",
            repo: "aerie",
            sortOrder: 0
        )
        try await insertRepo(
            db,
            id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000002")!,
            accountId: secondaryId,
            name: "Bridge",
            repo: "bridge",
            sortOrder: 1,
            defaultBranch: "develop"
        )
        try await insertRepo(
            db,
            id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000003")!,
            accountId: primaryId,
            name: "Cipher",
            repo: "cipher",
            sortOrder: 2
        )

        let vm = RepositoriesViewModel(db: db)
        await vm.refresh()

        XCTAssertEqual(vm.repos.count, 3)
        XCTAssertEqual(vm.accounts.count, 2)

        let view = ZStack {
            Backdrop()
            RepositoriesScreen(
                viewModel: vm,
                onRefreshAll: { },
                onAddRepo: { }
            )
        }
        .frame(width: 820, height: 600)

        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 600)))
    }
}
