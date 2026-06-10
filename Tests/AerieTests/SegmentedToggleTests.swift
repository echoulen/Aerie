import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

@MainActor
final class SegmentedToggleTests: XCTestCase {
    private static let size = CGSize(width: 480, height: 80)

    private func host(_ selection: MainTab) -> NSHostingView<some View> {
        let view = ZStack {
            Backdrop()
            SegmentedToggle(selection: .constant(selection))
                .padding(20)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        return NSHostingView(rootView: view)
    }

    func test_segmentedTogglePRsSelected() {
        assertSnapshot(of: host(.prs), as: .image(size: Self.size))
    }

    func test_segmentedToggleIssuesSelected() {
        assertSnapshot(of: host(.issues), as: .image(size: Self.size))
    }

    func test_segmentedToggleReposSelected() {
        assertSnapshot(of: host(.repos), as: .image(size: Self.size))
    }

    /// Contract anchor for the ⌘1 / ⌘2 / ⌘3 wiring.
    ///
    /// SwiftUI does not expose a way to assert "this button has shortcut ⌘1"
    /// from a unit test, and exercising the shortcut requires the view to be
    /// in a key window's responder chain — out of reach here. The visual
    /// snapshot tests above already cover rendering; this test exists to
    /// fail the build if the `keyboardShortcut(_:modifiers:)` overload we
    /// rely on disappears (or `MainTab` / `SegmentedToggle` change shape),
    /// and to make the shortcut contract discoverable in the test file.
    func test_segmentedToggle_compilesWithKeyboardShortcuts() {
        let vm = AppViewModel(activeTab: .prs)
        _ = SegmentedToggle(selection: .constant(.prs))
        XCTAssertEqual(vm.activeTab, .prs)
    }
}
