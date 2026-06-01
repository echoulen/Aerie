import XCTest
import GRDB
@testable import Aerie

/// Logic coverage for the Settings → Appearance interface-zoom view model.
/// Mirrors the temp-DB pattern used by `AdvancedViewModelTests`: each test
/// spins up a throwaway SQLite file and exercises the real `SettingsDAO`.
final class AppearanceViewModelTests: XCTestCase {
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

    private func makeVM(_ db: AppDatabase) -> AppearanceViewModel {
        AppearanceViewModel(db: db)
    }

    // MARK: - Defaults

    func test_refresh_defaultsTo100_whenNothingPersisted() async throws {
        let db = try makeDB()
        let vm = makeVM(db)

        await vm.refresh()

        XCTAssertEqual(vm.zoomPct, 100)
        XCTAssertEqual(vm.activeIndex, AppearanceViewModel.defaultIndex)
    }

    func test_stops_matchDesign() {
        XCTAssertEqual(AppearanceViewModel.stops.map(\.pct), [85, 92, 100, 110, 125])
        XCTAssertEqual(AppearanceViewModel.stops.map(\.label),
                       ["Smaller", "Small", "Default", "Large", "Larger"])
        XCTAssertEqual(AppearanceViewModel.stops[AppearanceViewModel.defaultIndex].pct, 100)
    }

    // MARK: - Load

    func test_refresh_loadsPersistedStop() async throws {
        let db = try makeDB()
        try await db.settings.setInt("appearance.zoom_pct", 110)

        let vm = makeVM(db)
        await vm.refresh()

        XCTAssertEqual(vm.zoomPct, 110)
        XCTAssertEqual(vm.activeIndex, 3)
    }

    func test_refresh_unknownPersistedValue_fallsBackToDefault() async throws {
        let db = try makeDB()
        // A value that is not one of the five stops (e.g. legacy/garbage).
        try await db.settings.setInt("appearance.zoom_pct", 137)

        let vm = makeVM(db)
        await vm.refresh()

        XCTAssertEqual(vm.zoomPct, 100)
        XCTAssertEqual(vm.activeIndex, AppearanceViewModel.defaultIndex)
    }

    // MARK: - Select

    func test_select_setsStopAndPersists() async throws {
        let db = try makeDB()
        let vm = makeVM(db)

        await vm.select(4)

        XCTAssertEqual(vm.activeIndex, 4)
        XCTAssertEqual(vm.zoomPct, 125)
        let persisted = try await db.settings.getInt("appearance.zoom_pct")
        XCTAssertEqual(persisted, 125)
    }

    func test_select_clampsOutOfRangeIndices() async throws {
        let db = try makeDB()
        let vm = makeVM(db)

        await vm.select(99)
        XCTAssertEqual(vm.activeIndex, AppearanceViewModel.stops.count - 1)
        XCTAssertEqual(vm.zoomPct, 125)

        await vm.select(-5)
        XCTAssertEqual(vm.activeIndex, 0)
        XCTAssertEqual(vm.zoomPct, 85)
    }

    // MARK: - Zoom in / out

    func test_zoomIn_movesUpOneStop_andClampsAtTop() async throws {
        let db = try makeDB()
        let vm = makeVM(db)            // starts at index 2 (100%)

        await vm.zoomIn()
        XCTAssertEqual(vm.zoomPct, 110)

        await vm.zoomIn()              // 125%
        await vm.zoomIn()             // clamp — already at top
        XCTAssertEqual(vm.activeIndex, AppearanceViewModel.stops.count - 1)
        XCTAssertEqual(vm.zoomPct, 125)

        let persisted = try await db.settings.getInt("appearance.zoom_pct")
        XCTAssertEqual(persisted, 125)
    }

    func test_zoomOut_movesDownOneStop_andClampsAtBottom() async throws {
        let db = try makeDB()
        let vm = makeVM(db)

        await vm.zoomOut()            // 92%
        XCTAssertEqual(vm.zoomPct, 92)

        await vm.zoomOut()            // 85%
        await vm.zoomOut()            // clamp
        XCTAssertEqual(vm.activeIndex, 0)
        XCTAssertEqual(vm.zoomPct, 85)
    }

    // MARK: - Reset

    func test_reset_returnsTo100_andPersists() async throws {
        let db = try makeDB()
        let vm = makeVM(db)

        await vm.select(0)            // 85%
        await vm.reset()

        XCTAssertEqual(vm.zoomPct, 100)
        XCTAssertEqual(vm.activeIndex, AppearanceViewModel.defaultIndex)
        let persisted = try await db.settings.getInt("appearance.zoom_pct")
        XCTAssertEqual(persisted, 100)
    }
}
