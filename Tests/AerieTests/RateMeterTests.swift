import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `RateMeter` across the three color bands defined
/// by the spec — healthy (> 90% green), warning (30–90% amber), and
/// danger (< 30% red).
final class RateMeterTests: XCTestCase {
    private func host(remaining: Int, limit: Int) -> NSHostingView<some View> {
        let view = ZStack {
            AerieColor.backdrop1
            RateMeter(remaining: remaining, limit: limit)
                .padding(.horizontal, 16)
        }
        .frame(width: 280, height: 40)
        return NSHostingView(rootView: view)
    }

    func test_rateMeter_healthy() {
        let host = host(remaining: 4800, limit: 5000)  // 96% — green
        assertSnapshot(of: host, as: .image(size: CGSize(width: 280, height: 40)))
    }

    func test_rateMeter_warning() {
        let host = host(remaining: 2500, limit: 5000)  // 50% — amber
        assertSnapshot(of: host, as: .image(size: CGSize(width: 280, height: 40)))
    }

    func test_rateMeter_danger() {
        let host = host(remaining: 500, limit: 5000)  // 10% — red
        assertSnapshot(of: host, as: .image(size: CGSize(width: 280, height: 40)))
    }
}
