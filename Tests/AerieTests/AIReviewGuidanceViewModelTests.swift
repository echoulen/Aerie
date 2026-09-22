import XCTest
@testable import Aerie

@MainActor
final class AIReviewGuidanceViewModelTests: XCTestCase {
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

    func test_freshDB_showsDefaults() async throws {
        let vm = AIReviewGuidanceViewModel(db: try makeDB())
        await vm.refresh()
        XCTAssertEqual(vm.text(.firstPass), AIReviewGuidance.defaultFirstPass)
        XCTAssertEqual(vm.text(.followUp), AIReviewGuidance.defaultFollowUp)
        XCTAssertFalse(vm.isCustom(.firstPass))
    }

    func test_edit_savesAfterDebounce_andSurvivesReload() async throws {
        let db = try makeDB()
        let vm = AIReviewGuidanceViewModel(db: db, debounce: .milliseconds(10))
        vm.setText("flag force unwraps", for: .firstPass)
        XCTAssertTrue(vm.isCustom(.firstPass))
        try await Task.sleep(for: .milliseconds(200))
        let stored = try await db.settings.getString(AIReviewGuidance.firstPassKey)
        XCTAssertEqual(stored, "flag force unwraps")

        let reloaded = AIReviewGuidanceViewModel(db: db)
        await reloaded.refresh()
        XCTAssertEqual(reloaded.text(.firstPass), "flag force unwraps")
    }

    func test_reset_clearsStoredValue() async throws {
        let db = try makeDB()
        let vm = AIReviewGuidanceViewModel(db: db, debounce: .seconds(60))
        vm.setText("custom follow-up", for: .followUp)
        await vm.flush()
        let saved = try await db.settings.getString(AIReviewGuidance.followUpKey)
        XCTAssertNotNil(saved)

        await vm.reset(.followUp)
        XCTAssertEqual(vm.text(.followUp), AIReviewGuidance.defaultFollowUp)
        XCTAssertFalse(vm.isCustom(.followUp))
        let cleared = try await db.settings.getString(AIReviewGuidance.followUpKey)
        XCTAssertNil(cleared)
    }

    func test_blankOrDefaultText_isNotStored() {
        XCTAssertNil(AIReviewGuidanceViewModel.storedValue("   ", for: .firstPass))
        XCTAssertNil(AIReviewGuidanceViewModel.storedValue(AIReviewGuidance.defaultFirstPass + "\n", for: .firstPass))
        XCTAssertEqual(AIReviewGuidanceViewModel.storedValue("x", for: .firstPass), "x")
    }

    func test_lockedSections_comeFromThePromptBuilder() async throws {
        let vm = AIReviewGuidanceViewModel(db: try makeDB())
        XCTAssertTrue(vm.lockedHead(.firstPass).contains("PR #{{NUMBER}}: {{TITLE}}"))
        XCTAssertTrue(vm.lockedTail(.firstPass).contains(ClaudeReviewPrompt.contract(followUp: false)))
        XCTAssertTrue(vm.lockedTail(.followUp).contains(ClaudeReviewPrompt.replyGuard))
    }
}
