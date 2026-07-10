import XCTest
@testable import Aerie

/// Mirrors the temp-DB pattern used by `AppearanceViewModelTests` /
/// `PRPublishViewModelTests`: each test spins up a throwaway SQLite file and
/// exercises the real `SettingsDAO`.
@MainActor
final class AIModelViewModelTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs.removeAll()
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    private func makeVM(_ db: AppDatabase) -> AIModelViewModel {
        AIModelViewModel(db: db)
    }

    func test_refresh_noStoredValue_defaultsToSonnet5() async throws {
        let vm = makeVM(try makeDB())
        await vm.refresh()
        XCTAssertEqual(vm.selected, .sonnet5)
    }

    func test_refresh_loadsPersistedModel() async throws {
        let db = try makeDB()
        try await db.settings.setString(AIModelViewModel.settingsKey, ClaudeModel.opus48.rawValue)
        let vm = makeVM(db)
        await vm.refresh()
        XCTAssertEqual(vm.selected, .opus48)
    }

    func test_refresh_unknownPersistedValue_fallsBackToDefault() async throws {
        let db = try makeDB()
        try await db.settings.setString(AIModelViewModel.settingsKey, "claude-legacy-1")
        let vm = makeVM(db)
        await vm.refresh()
        XCTAssertEqual(vm.selected, .sonnet5)
    }

    func test_setModel_updatesSelectionAndPersists() async throws {
        let db = try makeDB()
        let vm = makeVM(db)
        await vm.refresh()

        await vm.setModel(.haiku45)

        XCTAssertEqual(vm.selected, .haiku45)
        let stored = try await db.settings.getString(AIModelViewModel.settingsKey)
        XCTAssertEqual(stored, "claude-haiku-4-5-20251001")
    }
}
