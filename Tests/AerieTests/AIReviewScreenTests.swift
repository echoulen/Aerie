import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for Settings → AI Review, following `AIModelScreenTests`.
@MainActor
final class AIReviewScreenTests: XCTestCase {
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

    private func snapshot(_ vm: AIReviewGuidanceViewModel, file: StaticString = #file, testName: String = #function) {
        let view = ZStack {
            Backdrop(showsPlanets: false)
            AIReviewScreen(viewModel: vm)
        }
        .frame(width: 820, height: 1130)
        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 1130)), file: file, testName: testName)
    }

    func test_firstPass_custom() async throws {
        let vm = AIReviewGuidanceViewModel(db: try makeDB(), debounce: .seconds(60))
        await vm.refresh()
        vm.setText(AIReviewGuidance.defaultFirstPass + "\n\nProject-specific rules:\n- Flag Task.sleep outside a Clock abstraction.", for: .firstPass)
        snapshot(vm)
    }

    func test_followUp_default() async throws {
        let vm = AIReviewGuidanceViewModel(db: try makeDB())
        await vm.refresh()
        vm.tab = .followUp
        snapshot(vm)
    }
}
