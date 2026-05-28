import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class AppFrameTests: XCTestCase {
    private func host(activeTab: MainTab, nextTickInSeconds: Int?) -> NSHostingView<some View> {
        let vm = AppViewModel(activeTab: activeTab, nextTickInSeconds: nextTickInSeconds)
        let view = AppFrame(viewModel: vm) {
            // Placeholder content — the real PRs/Repos views land in later phases.
            Text("Content area")
                .font(AerieFont.body())
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
}
