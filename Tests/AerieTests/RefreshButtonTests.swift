import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class RefreshButtonTests: XCTestCase {
    /// The `action` closure is the contract MainShell relies on: ⌘R (and a
    /// click) must run it. SwiftUI doesn't let a headless test fire the
    /// `keyboardShortcut(_:modifiers:)` we attach (that needs a key window's
    /// responder chain — see the matching note in `SegmentedToggleTests`), so
    /// this exercises the action wiring directly and anchors the button's shape:
    /// the build fails if `RefreshButton`'s `action` initializer disappears.
    func test_refreshButton_runsActionWhenInvoked() async {
        let ran = expectation(description: "action ran")
        let button = RefreshButton(action: { ran.fulfill() })
        await button.action()
        await fulfillment(of: [ran], timeout: 1.0)
    }
}
