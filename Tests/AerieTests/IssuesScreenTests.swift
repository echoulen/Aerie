import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the full Issues screen at the main-window content
/// size. Seeds a temp DB with issues across 2 repos, refreshes a real
/// `IssuesViewModel`, then renders the screen against the standard backdrop.
@MainActor
final class IssuesScreenTests: XCTestCase {
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

    func test_issuesScreenSnapshot_threeRows() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let aerie = try await insertRepo(db, accountId: acct, name: "aerie", repo: "aerie")
        let shrike = try await insertRepo(db, accountId: acct, name: "shrike", repo: "shrike-renderer")

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let i1 = Issue(
            id: UUID(uuidString: "31000000-0000-0000-0000-000000000001")!,
            repoId: aerie.id, number: 148,
            title: "Polling backs off too aggressively after a 403",
            authorLogin: "maja-c", assignedToMe: true, assigneeLogins: ["carlos-li"],
            labels: [IssueLabel(name: "bug", color: "d73a4a"), IssueLabel(name: "polling", color: "0e8a16")],
            commentCount: 6,
            htmlUrl: URL(string: "https://github.com/carlos-li/aerie/issues/148")!,
            updatedAt: base.addingTimeInterval(300)
        )
        let i2 = Issue(
            id: UUID(uuidString: "31000000-0000-0000-0000-000000000002")!,
            repoId: aerie.id, number: 146,
            title: "Add keyboard shortcut to refresh the active list",
            authorLogin: "carlos-li", assignedToMe: true, assigneeLogins: ["carlos-li"],
            labels: [IssueLabel(name: "enhancement", color: "a2eeef")],
            commentCount: 2,
            htmlUrl: URL(string: "https://github.com/carlos-li/aerie/issues/146")!,
            updatedAt: base.addingTimeInterval(200)
        )
        let i3 = Issue(
            id: UUID(uuidString: "31000000-0000-0000-0000-000000000003")!,
            repoId: shrike.id, number: 204,
            title: "Glyph cache leaks under rapid re-render",
            authorLogin: "jens-h", assignedToMe: false, assigneeLogins: [],
            labels: [IssueLabel(name: "perf", color: "fbca04")],
            commentCount: 11,
            htmlUrl: URL(string: "https://github.com/carlos-li/shrike-renderer/issues/204")!,
            updatedAt: base.addingTimeInterval(100)
        )

        try await db.issueCache.upsert([i1, i2], for: aerie.id)
        try await db.issueCache.upsert([i3], for: shrike.id)

        let vm = IssuesViewModel(db: db)
        await vm.refresh()

        guard case .ready(let rows) = vm.state else {
            XCTFail("Expected .ready, got \(vm.state)")
            return
        }
        XCTAssertEqual(rows.count, 3)

        let fixedNow = Date(timeIntervalSince1970: 1_700_010_000)
        let view = ZStack {
            Backdrop()
            IssuesScreen(viewModel: vm, now: fixedNow, tabSelection: .constant(.issues))
        }
        .frame(width: 1240, height: 760)

        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 1240, height: 760)))
    }
}
