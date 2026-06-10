import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the full Accounts screen at the Settings content
/// size. Seeds a temp DB with 2 accounts (one primary, one secondary)
/// plus a sprinkling of repos pointing at each, then refreshes a real
/// `AccountsViewModel` and snapshots the rendered view.
@MainActor
final class AccountsScreenTests: XCTestCase {
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
        accountId: UUID,
        name: String,
        sortOrder: Int
    ) async throws {
        let r = Repository(
            id: UUID(),
            name: name,
            localPath: URL(fileURLWithPath: "/opt/repos/\(name)"),
            githubOwner: "carlos-li",
            githubRepo: name.lowercased(),
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: sortOrder,
            hidden: false
        )
        try await db.repos.insert(r)
    }

    /// Stub usage tracker that returns a pre-seeded timestamp map.
    private actor PreseededUsage: AccountUsageTracker {
        private let values: [UUID: Date]
        init(_ values: [UUID: Date]) { self.values = values }
        func lastUsed(forAccount accountId: UUID) async -> Date? { values[accountId] }
    }

    func test_accountsScreen_twoAccountsPrimaryAndSecondary() async throws {
        let db = try makeDB()

        // Two stable IDs so the snapshot doesn't churn on UUID order.
        let primaryId   = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        let secondaryId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!

        let primary   = try insertAccount(db, id: primaryId, login: "carlos-li")
        _ = try insertAccount(db, id: secondaryId, login: "cli-work")

        // 3 repos under primary, 1 under secondary.
        try await insertRepo(db, accountId: primary.id, name: "Aerie",  sortOrder: 0)
        try await insertRepo(db, accountId: primary.id, name: "Bridge", sortOrder: 1)
        try await insertRepo(db, accountId: primary.id, name: "Cipher", sortOrder: 2)
        try await insertRepo(db, accountId: secondaryId, name: "Shrike", sortOrder: 3)

        // Pin "now" 5 minutes after the lastUsed stamp so "5m ago" is stable.
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_300)
        let lastUsed = Date(timeIntervalSince1970: 1_700_000_000)

        let tracker = PreseededUsage([
            primary.id: lastUsed,
            secondaryId: lastUsed,
        ])

        let vm = AccountsViewModel(
            db: db,
            api: tracker,
            scopesByAccount: {
                [
                    primary.id: ["repo", "read:org"],
                    secondaryId: ["repo"],
                ]
            },
            primaryAccountId: { primary.id }
        )
        await vm.refresh()

        // Sanity check before snapshotting.
        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertNil(vm.error)

        let view = ZStack {
            Backdrop()
            AccountsScreen(
                viewModel: vm,
                ghVersion: "gh version 2.74.0 (2025-05-29)",
                now: fixedNow
            )
        }
        .frame(width: 820, height: 760)

        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 760)))
    }
}
