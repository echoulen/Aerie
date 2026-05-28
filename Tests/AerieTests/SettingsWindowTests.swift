import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class SettingsWindowTests: XCTestCase {
    func test_settingsWindowSnapshot_accountsRoute() {
        let view = SettingsWindow()
            .frame(width: 1040, height: 760)
        assertSnapshot(of: NSHostingView(rootView: view),
                       as: .image(size: CGSize(width: 1040, height: 760)))
    }
}
