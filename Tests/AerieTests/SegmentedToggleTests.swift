import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class SegmentedToggleTests: XCTestCase {
    private func host(_ selection: MainTab) -> NSHostingView<some View> {
        let view = ZStack {
            Backdrop()
            SegmentedToggle(selection: .constant(selection))
                .padding(20)
        }
        .frame(width: 320, height: 80)
        return NSHostingView(rootView: view)
    }

    func test_segmentedTogglePRsSelected() {
        assertSnapshot(
            of: host(.prs),
            as: .image(size: CGSize(width: 320, height: 80))
        )
    }

    func test_segmentedToggleReposSelected() {
        assertSnapshot(
            of: host(.repos),
            as: .image(size: CGSize(width: 320, height: 80))
        )
    }
}
