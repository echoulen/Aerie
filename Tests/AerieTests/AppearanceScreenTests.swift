import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the Settings → Appearance screen at the Settings
/// content size. Seeds a temp DB, drives an `AppearanceViewModel` to a known
/// stop, then renders. Two cases pin the visual contract: the default 100%
/// stop, and a zoomed-in 125% stop (the preview row scales with it).
@MainActor
final class AppearanceScreenTests: XCTestCase {
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

    func test_appearanceScreen_default100() async throws {
        let db = try makeDB()
        let vm = AppearanceViewModel(db: db)
        await vm.refresh()  // defaults to 100%
        XCTAssertEqual(vm.zoomPct, 100)

        await MainActor.run {
            let view = ZStack {
                Backdrop()
                AppearanceScreen(viewModel: vm)
            }
            .frame(width: 820, height: 760)
            let host = NSHostingView(rootView: view)
            assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 760)))
        }
    }

    func test_appearanceScreen_larger125() async throws {
        let db = try makeDB()
        let vm = AppearanceViewModel(db: db)
        await vm.select(4)  // 125% — "Larger"
        XCTAssertEqual(vm.zoomPct, 125)

        await MainActor.run {
            let view = ZStack {
                Backdrop()
                AppearanceScreen(viewModel: vm)
            }
            .frame(width: 820, height: 760)
            let host = NSHostingView(rootView: view)
            assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 760)))
        }
    }
}
