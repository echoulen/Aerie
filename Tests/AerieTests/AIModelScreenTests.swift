import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the Settings → AI Model screen, following the same
/// temp-DB + render pattern as `AppearanceScreenTests`.
@MainActor
final class AIModelScreenTests: XCTestCase {
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

    func test_aiModelScreen_defaultSonnet5() async throws {
        let db = try makeDB()
        let vm = AIModelViewModel(db: db)
        await vm.refresh()
        XCTAssertEqual(vm.selected, .sonnet5)

        await MainActor.run {
            let view = ZStack {
                Backdrop(showsPlanets: false)
                AIModelScreen(viewModel: vm)
            }
            .frame(width: 820, height: 760)
            let host = NSHostingView(rootView: view)
            assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 760)))
        }
    }

    func test_aiModelScreen_opus55Selected() async throws {
        let db = try makeDB()
        let vm = AIModelViewModel(db: db)
        await vm.setModel(.opus55)
        XCTAssertEqual(vm.selected, .opus55)

        await MainActor.run {
            let view = ZStack {
                Backdrop(showsPlanets: false)
                AIModelScreen(viewModel: vm)
            }
            .frame(width: 820, height: 760)
            let host = NSHostingView(rootView: view)
            assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 760)))
        }
    }
}
