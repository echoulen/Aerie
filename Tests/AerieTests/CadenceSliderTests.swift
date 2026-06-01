import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `CadenceSlider` at three positions: 30s (lower
/// end of the active range), 5 min (middle of the background range),
/// and 15 min (upper-mid of the background range). Each renders the
/// label + value text and the track/fill/knob composition.
final class CadenceSliderTests: XCTestCase {
    private func host(seconds: TimeInterval, label: String, range: ClosedRange<TimeInterval>) -> NSHostingView<some View> {
        // Snapshot uses a constant binding — the slider doesn't need
        // to mutate state, just render at the given position.
        let view = ZStack {
            AerieColor.backdrop1
            CadenceSlider(label: label, seconds: .constant(seconds), range: range)
                .padding(.horizontal, 16)
        }
        .frame(width: 320, height: 56)
        return NSHostingView(rootView: view)
    }

    func test_cadenceSlider_30s() {
        let host = host(seconds: 30, label: "Active", range: 15...600)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 56)))
    }

    func test_cadenceSlider_5min() {
        let host = host(seconds: 300, label: "Background", range: 60...3600)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 56)))
    }

    func test_cadenceSlider_15min() {
        let host = host(seconds: 900, label: "Background", range: 60...3600)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 320, height: 56)))
    }
}
