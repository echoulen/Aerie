import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class FirstRunViewsTests: XCTestCase {
    func test_noGhBody_snapshot() {
        let view = ZStack {
            Backdrop()
            NoGhBody(onRecheck: { })
        }
        .frame(width: 800, height: 560)

        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 800, height: 560)))
    }

    func test_noAuthBody_snapshot() {
        let view = ZStack {
            Backdrop()
            NoAuthBody(onRecheck: { })
        }
        .frame(width: 800, height: 560)

        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 800, height: 560)))
    }
}
