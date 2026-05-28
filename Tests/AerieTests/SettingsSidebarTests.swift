import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class SettingsSidebarTests: XCTestCase {
    func test_sidebarSnapshot_accountsSelected() {
        let view = SettingsSidebar(selection: .constant(.accounts), mcpRunning: false)
            .frame(width: 220, height: 760)
            .background(AerieColor.backdrop1)
        assertSnapshot(of: NSHostingView(rootView: view),
                       as: .image(size: CGSize(width: 220, height: 760)))
    }

    func test_sidebarSnapshot_mcpSelectedAndRunning() {
        let view = SettingsSidebar(selection: .constant(.mcp), mcpRunning: true)
            .frame(width: 220, height: 760)
            .background(AerieColor.backdrop1)
        assertSnapshot(of: NSHostingView(rootView: view),
                       as: .image(size: CGSize(width: 220, height: 760)))
    }

    func test_sidebarSnapshot_aboutAtBottom() {
        let view = SettingsSidebar(selection: .constant(.about), mcpRunning: false)
            .frame(width: 220, height: 760)
            .background(AerieColor.backdrop1)
        assertSnapshot(of: NSHostingView(rootView: view),
                       as: .image(size: CGSize(width: 220, height: 760)))
    }
}
