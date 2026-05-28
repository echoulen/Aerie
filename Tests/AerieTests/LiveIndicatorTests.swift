import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class LiveIndicatorTests: XCTestCase {
    private func host(_ value: Int?) -> NSHostingView<some View> {
        let view = ZStack {
            AerieColor.backdrop1
            LiveIndicator(nextTickInSeconds: value)
                .padding(.horizontal, 16)
        }
        .frame(width: 160, height: 32)
        return NSHostingView(rootView: view)
    }

    func test_liveIndicator_live14s() {
        assertSnapshot(
            of: host(14),
            as: .image(size: CGSize(width: 160, height: 32))
        )
    }

    func test_liveIndicator_paused() {
        assertSnapshot(
            of: host(nil),
            as: .image(size: CGSize(width: 160, height: 32))
        )
    }
}
