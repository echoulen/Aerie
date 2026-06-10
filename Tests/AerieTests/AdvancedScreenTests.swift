import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the full Advanced screen at the Settings content
/// size. Seeds a temp DB with two accounts + rate-limit snapshots (one
/// healthy, one warning), refreshes a real `AdvancedViewModel`, then
/// snapshots the rendered view.
@MainActor
final class AdvancedScreenTests: XCTestCase {
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

    func test_advancedScreen_seeded() async throws {
        let db = try makeDB()

        let healthyId = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        let warningId = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000002")!
        _ = try insertAccount(db, id: healthyId, login: "carlos-li")
        _ = try insertAccount(db, id: warningId, login: "cli-work")

        // Seed defaults so the VM picks them up explicitly (verifies the
        // "loaded from DB" branch, not the "fall back to default" branch).
        try await db.settings.setInt("polling.active_seconds", 30)
        try await db.settings.setInt("polling.background_seconds", 300)
        try await db.settings.setBool("behavior.refresh_on_focus", true)
        try await db.settings.setBool("behavior.pause_on_blur", true)

        let healthySnap = RateLimitSnapshot(remaining: 4800, resetEpoch: 1_700_000_000, limit: 5000)
        let warningSnap = RateLimitSnapshot(remaining: 2500, resetEpoch: 1_700_000_000, limit: 5000)
        let provider: (UUID) async -> RateLimitSnapshot? = { id in
            switch id {
            case healthyId: return healthySnap
            case warningId: return warningSnap
            default: return nil
            }
        }

        let vm = AdvancedViewModel(
            db: db,
            cadenceApplier: { _, _ in },
            rateLimitProvider: provider
        )
        await vm.refresh()

        XCTAssertEqual(vm.activeCadence, 30)
        XCTAssertEqual(vm.backgroundCadence, 300)
        XCTAssertEqual(vm.rateLimits.count, 2)

        // Render + snapshot are pinned to the main actor so SwiftUI's
        // body evaluation doesn't trip the executor-isolation check —
        // AdvancedScreen's nested `Toggle(isOn:)` bindings interact with
        // `@Bindable` state that strict-concurrency considers main-only.
        await MainActor.run {
            let view = ZStack {
                Backdrop()
                AdvancedScreen(viewModel: vm)
            }
            .frame(width: 820, height: 760)

            let host = NSHostingView(rootView: view)
            assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 760)))
        }
    }
}
