import XCTest
@testable import Aerie

@MainActor
final class PRPublishViewModelTests: XCTestCase {
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

    /// Short debounce so tests can await persistence quickly.
    private func makeVM(_ db: AppDatabase) -> PRPublishViewModel {
        PRPublishViewModel(db: db, debounceMilliseconds: 20)
    }

    private func awaitDebounce() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func test_refresh_noStoredValue_showsDefault() async throws {
        let vm = makeVM(try makeDB())
        await vm.refresh()
        XCTAssertEqual(vm.template, DefaultPRPublishTemplate.text)
        XCTAssertFalse(vm.isCustom)
    }

    func test_refresh_storedValue_showsCustom() async throws {
        let db = try makeDB()
        try await db.settings.setString(PRPublishViewModel.settingsKey, "my template")
        let vm = makeVM(db)
        await vm.refresh()
        XCTAssertEqual(vm.template, "my template")
        XCTAssertTrue(vm.isCustom)
    }

    func test_setTemplate_persistsAfterDebounce() async throws {
        let db = try makeDB()
        let vm = makeVM(db)
        await vm.refresh()
        vm.setTemplate("edited")
        XCTAssertEqual(vm.template, "edited")   // immediate in-memory
        await awaitDebounce()
        let stored = try await db.settings.getString(PRPublishViewModel.settingsKey)
        XCTAssertEqual(stored, "edited")
    }

    func test_setTemplate_rapidEdits_lastWins() async throws {
        let db = try makeDB()
        let vm = makeVM(db)
        await vm.refresh()
        vm.setTemplate("one")
        vm.setTemplate("two")
        vm.setTemplate("three")
        await awaitDebounce()
        let stored = try await db.settings.getString(PRPublishViewModel.settingsKey)
        XCTAssertEqual(stored, "three")
    }

    func test_setTemplate_backToDefaultText_deletesKey() async throws {
        let db = try makeDB()
        try await db.settings.setString(PRPublishViewModel.settingsKey, "custom")
        let vm = makeVM(db)
        await vm.refresh()
        vm.setTemplate(DefaultPRPublishTemplate.text)
        await awaitDebounce()
        let stored = try await db.settings.getString(PRPublishViewModel.settingsKey)
        XCTAssertNil(stored)
        XCTAssertFalse(vm.isCustom)
    }

    func test_setTemplate_blank_deletesKey() async throws {
        let db = try makeDB()
        try await db.settings.setString(PRPublishViewModel.settingsKey, "custom")
        let vm = makeVM(db)
        await vm.refresh()
        vm.setTemplate("   \n")
        await awaitDebounce()
        let stored = try await db.settings.getString(PRPublishViewModel.settingsKey)
        XCTAssertNil(stored)
    }

    func test_resetToDefault_restoresTextAndDeletesKey() async throws {
        let db = try makeDB()
        try await db.settings.setString(PRPublishViewModel.settingsKey, "custom")
        let vm = makeVM(db)
        await vm.refresh()
        await vm.resetToDefault()
        XCTAssertEqual(vm.template, DefaultPRPublishTemplate.text)
        XCTAssertFalse(vm.isCustom)
        let stored = try await db.settings.getString(PRPublishViewModel.settingsKey)
        XCTAssertNil(stored)
    }
}
