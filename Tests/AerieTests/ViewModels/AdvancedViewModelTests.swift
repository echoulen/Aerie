import XCTest
import GRDB
@testable import Aerie

/// Recording stub for the `cadenceApplier` closure. The VM is the only
/// source of truth for what cadences the scheduler should be running on,
/// so tests just need to verify the closure fires with the right tuple.
private final class CadenceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(TimeInterval, TimeInterval)] = []

    func record(_ active: TimeInterval, _ bg: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        calls.append((active, bg))
    }

    var lastCall: (TimeInterval, TimeInterval)? {
        lock.lock(); defer { lock.unlock() }
        return calls.last
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls.count
    }
}

@MainActor
final class AdvancedViewModelTests: XCTestCase {
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
    private func insertAccount(
        _ db: AppDatabase,
        id: UUID = UUID(),
        login: String = "tester",
        host: String = "github.com"
    ) throws -> GitHubAccount {
        let acct = GitHubAccount(id: id, login: login, host: host)
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [acct.id.uuidString, acct.login, acct.host]
            )
        }
        return acct
    }

    private func makeVM(
        db: AppDatabase,
        recorder: CadenceRecorder = CadenceRecorder(),
        rateLimitProvider: @escaping (UUID) async -> RateLimitSnapshot? = { _ in nil }
    ) -> AdvancedViewModel {
        AdvancedViewModel(
            db: db,
            cadenceApplier: { active, bg in recorder.record(active, bg) },
            rateLimitProvider: rateLimitProvider
        )
    }

    // MARK: - Tests

    func test_refresh_loadsDefaults_whenNothingPersisted() async throws {
        let db = try makeDB()
        let vm = makeVM(db: db)

        await vm.refresh()

        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.activeCadence, 30)
        XCTAssertEqual(vm.backgroundCadence, 300)
        XCTAssertTrue(vm.refreshOnFocus)
        XCTAssertTrue(vm.pauseOnBlur)
        XCTAssertTrue(vm.rateLimits.isEmpty)
    }

    func test_refresh_loadsPersistedValues() async throws {
        let db = try makeDB()
        try await db.settings.setInt("polling.active_seconds", 60)
        try await db.settings.setInt("polling.background_seconds", 600)
        try await db.settings.setBool("behavior.refresh_on_focus", false)
        try await db.settings.setBool("behavior.pause_on_blur", false)

        let vm = makeVM(db: db)
        await vm.refresh()

        XCTAssertEqual(vm.activeCadence, 60)
        XCTAssertEqual(vm.backgroundCadence, 600)
        XCTAssertFalse(vm.refreshOnFocus)
        XCTAssertFalse(vm.pauseOnBlur)
    }

    func test_setActiveCadence_persistsAndNotifiesScheduler() async throws {
        let db = try makeDB()
        let recorder = CadenceRecorder()
        let vm = makeVM(db: db, recorder: recorder)

        await vm.setActiveCadence(45)

        XCTAssertEqual(vm.activeCadence, 45)
        let persisted = try await db.settings.getInt("polling.active_seconds")
        XCTAssertEqual(persisted, 45)

        let last = recorder.lastCall
        XCTAssertEqual(last?.0, 45)
        XCTAssertEqual(last?.1, 300)  // bg default untouched
        XCTAssertEqual(recorder.callCount, 1)
    }

    func test_setBackgroundCadence_clampsAtActive() async throws {
        let db = try makeDB()
        let recorder = CadenceRecorder()
        let vm = makeVM(db: db, recorder: recorder)

        // Bring active up first so the clamp has bite.
        await vm.setActiveCadence(120)
        // Try to set background below active — should be clamped.
        await vm.setBackgroundCadence(60)

        XCTAssertEqual(vm.backgroundCadence, 120)
        let persisted = try await db.settings.getInt("polling.background_seconds")
        XCTAssertEqual(persisted, 120)

        let last = recorder.lastCall
        XCTAssertEqual(last?.0, 120)
        XCTAssertEqual(last?.1, 120)
    }

    func test_setRefreshOnFocus_persists() async throws {
        let db = try makeDB()
        let vm = makeVM(db: db)

        await vm.setRefreshOnFocus(false)

        XCTAssertFalse(vm.refreshOnFocus)
        let persisted = try await db.settings.getBool("behavior.refresh_on_focus")
        XCTAssertEqual(persisted, false)
    }

    func test_setPauseOnBlur_persists() async throws {
        let db = try makeDB()
        let vm = makeVM(db: db)

        await vm.setPauseOnBlur(false)

        XCTAssertFalse(vm.pauseOnBlur)
        let persisted = try await db.settings.getBool("behavior.pause_on_blur")
        XCTAssertEqual(persisted, false)
    }

    func test_resetToDefaults_restoresAll_andNotifies() async throws {
        let db = try makeDB()
        let recorder = CadenceRecorder()
        let vm = makeVM(db: db, recorder: recorder)

        // Set everything to non-default values first.
        await vm.setActiveCadence(60)
        await vm.setBackgroundCadence(900)
        await vm.setRefreshOnFocus(false)
        await vm.setPauseOnBlur(false)

        let callsBeforeReset = recorder.callCount

        await vm.resetToDefaults()

        XCTAssertEqual(vm.activeCadence, AdvancedViewModel.defaultActive)
        XCTAssertEqual(vm.backgroundCadence, AdvancedViewModel.defaultBackground)
        XCTAssertTrue(vm.refreshOnFocus)
        XCTAssertTrue(vm.pauseOnBlur)

        let persistedActive = try await db.settings.getInt("polling.active_seconds")
        XCTAssertEqual(persistedActive, Int(AdvancedViewModel.defaultActive))
        let persistedBg = try await db.settings.getInt("polling.background_seconds")
        XCTAssertEqual(persistedBg, Int(AdvancedViewModel.defaultBackground))
        let persistedFocus = try await db.settings.getBool("behavior.refresh_on_focus")
        XCTAssertEqual(persistedFocus, true)
        let persistedBlur = try await db.settings.getBool("behavior.pause_on_blur")
        XCTAssertEqual(persistedBlur, true)

        // Reset should have produced exactly one additional applier call.
        XCTAssertEqual(recorder.callCount, callsBeforeReset + 1)
        let last = recorder.lastCall
        XCTAssertEqual(last?.0, AdvancedViewModel.defaultActive)
        XCTAssertEqual(last?.1, AdvancedViewModel.defaultBackground)
    }

    func test_refresh_populatesRateLimits_perAccount() async throws {
        let db = try makeDB()
        let acct1 = try insertAccount(db, login: "alpha")
        let acct2 = try insertAccount(db, login: "bravo")

        let snap = RateLimitSnapshot(remaining: 4321, resetEpoch: 1_700_000_000, limit: 5000)
        let provider: (UUID) async -> RateLimitSnapshot? = { id in
            id == acct1.id ? snap : nil
        }
        let vm = makeVM(db: db, rateLimitProvider: provider)

        await vm.refresh()

        XCTAssertEqual(vm.rateLimits.count, 2)
        let alphaRow = try XCTUnwrap(vm.rateLimits.first { $0.account.id == acct1.id })
        XCTAssertEqual(alphaRow.snapshot, snap)
        let bravoRow = try XCTUnwrap(vm.rateLimits.first { $0.account.id == acct2.id })
        XCTAssertNil(bravoRow.snapshot)
    }
}
