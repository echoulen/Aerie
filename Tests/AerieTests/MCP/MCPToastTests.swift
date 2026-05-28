import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class MCPToastTests: XCTestCase {
    private func host<V: View>(_ view: V, size: CGSize) -> NSHostingView<some View> {
        let wrapper = ZStack {
            Backdrop()
            view
        }
        .frame(width: size.width, height: size.height)
        return NSHostingView(rootView: wrapper)
    }

    func test_mcpToast_snapshot_success() {
        let item = ToastItem(
            title: "Merged PR #42",
            subtitle: "owner/repo · 0.6s",
            tone: .success,
            requestJSON: "{}",
            responseJSON: "{}"
        )
        let view = MCPToast(item: item)
        let size = CGSize(width: 380, height: 120)
        assertSnapshot(of: host(view, size: size), as: .image(size: size))
    }

    func test_mcpToast_snapshot_error() {
        let item = ToastItem(
            title: "Hard reset failed",
            subtitle: "owner/repo · merge conflict",
            tone: .error,
            requestJSON: "{}",
            responseJSON: "{}"
        )
        let view = MCPToast(item: item)
        let size = CGSize(width: 380, height: 120)
        assertSnapshot(of: host(view, size: size), as: .image(size: size))
    }
}
