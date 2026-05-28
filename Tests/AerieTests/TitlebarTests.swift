import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class TitlebarTests: XCTestCase {
    /// Captures the bare titlebar shell — traffic lights + brand mark — at the
    /// production window width. The mid + trail slots are empty here.
    ///
    /// TODO(Task 8.1): once `SegmentedToggle` and `LiveIndicator` exist, add
    /// state-variant snapshots ("PRs active" / "Repos active") that fill the
    /// `mid` and `trail` slots — this is the plan's original
    /// "with both PRs/Repos active states" coverage.
    func test_titlebarShellSnapshot() {
        let view = ZStack {
            AerieColor.backdrop1
            VStack(spacing: 0) {
                Titlebar()
                Spacer()
            }
        }
        .frame(width: 1240, height: 44)

        assertSnapshot(
            of: NSHostingView(rootView: view),
            as: .image(size: CGSize(width: 1240, height: 44))
        )
    }
}
