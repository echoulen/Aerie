import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

@MainActor
final class AppFrameTests: XCTestCase {
    private func host(activeTab: MainTab, nextTickInSeconds: Int?) -> NSHostingView<some View> {
        let vm = AppViewModel(activeTab: activeTab, nextTickInSeconds: nextTickInSeconds)
        let view = AppFrame(viewModel: vm) {
            // Placeholder content — the real PRs/Repos views land in later phases.
            Text("Content area")
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(width: AerieMetric.mainWindowW, height: AerieMetric.mainWindowH)
        return NSHostingView(rootView: view)
    }

    func test_appFrameSnapshot_prsActive() {
        assertSnapshot(
            of: host(activeTab: .prs, nextTickInSeconds: 14),
            as: .image(size: CGSize(width: AerieMetric.mainWindowW, height: AerieMetric.mainWindowH))
        )
    }

    func test_appFrameSnapshot_reposActive() {
        assertSnapshot(
            of: host(activeTab: .repos, nextTickInSeconds: 14),
            as: .image(size: CGSize(width: AerieMetric.mainWindowW, height: AerieMetric.mainWindowH))
        )
    }

    /// Chrome at the narrower tiers: the frame measures its own width, so a
    /// 880pt window moves the tab switch into the titlebar and a 560pt one puts
    /// a tab strip under a mark-only titlebar.
    private func tabbedHost(width: CGFloat) -> NSHostingView<some View> {
        let vm = AppViewModel(activeTab: .prs, nextTickInSeconds: 14)
        let bar = MainTabBar(selection: .constant(.prs), counts: [.prs: 13, .issues: 6, .repos: 9])
        let view = AppFrame(viewModel: vm, tabBar: bar) {
            Text("Content area")
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(width: width, height: AerieMetric.mainWindowH)
        return NSHostingView(rootView: view)
    }

    func test_appFrameSnapshot_mediumTabsInTitlebar() {
        assertSnapshot(of: tabbedHost(width: 880), as: .image(size: CGSize(width: 880, height: AerieMetric.mainWindowH)))
    }

    func test_appFrameSnapshot_compactTabStrip() {
        assertSnapshot(of: tabbedHost(width: 560), as: .image(size: CGSize(width: 560, height: AerieMetric.mainWindowH)))
    }
}
