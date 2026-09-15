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

    func test_sidebarSnapshot_appearanceSelected() {
        let view = SettingsSidebar(selection: .constant(.appearance), mcpRunning: false)
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

    // MARK: - Interface zoom

    /// Height the sidebar wants for `selection` with the given badges, at
    /// `scale`. A label that wraps adds a line, so it shows up as extra height.
    @MainActor
    private func idealHeight(scale: CGFloat, repositoriesCount: Int?, aiModelName: String?) -> CGFloat {
        let view = SettingsSidebar(selection: .constant(.repositories), mcpRunning: true,
                                   accountsCount: 0, repositoriesCount: repositoriesCount,
                                   aiModelName: aiModelName)
            .environment(\.interfaceFontScale, scale)
        let host = NSHostingView(rootView: view)
        return host.fittingSize.height
    }

    /// At the largest interface zoom (125%), "Repositories" next to its count
    /// wrapped onto a second line because the sidebar was a fixed 220pt while
    /// the labels scaled.
    @MainActor
    func test_labelsNeverWrap_atTheLargestZoom_withBadges() {
        let largest = CGFloat(AppearanceViewModel.stops.map(\.pct).max()!) / 100
        let bare = idealHeight(scale: largest, repositoriesCount: nil, aiModelName: nil)
        let badged = idealHeight(scale: largest, repositoriesCount: 17, aiModelName: "haiku")
        XCTAssertEqual(badged, bare, accuracy: 0.5, "a badge must never push its label onto a second line")
    }

    @MainActor
    func test_sidebarKeepsItsDesignWidth_atDefaultZoom() {
        let view = SettingsSidebar(selection: .constant(.repositories), mcpRunning: true,
                                   accountsCount: 3, repositoriesCount: 17, aiModelName: "haiku")
            .environment(\.interfaceFontScale, 1)
        XCTAssertEqual(NSHostingView(rootView: view).fittingSize.width, 220, accuracy: 0.5)
    }
}
