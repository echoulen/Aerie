import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class MCPConsentDialogTests: XCTestCase {
    func test_mcpConsentDialog_snapshot() {
        let view = ZStack {
            Backdrop()
            MCPConsentDialog(
                onAllow: { },
                onDecline: { }
            )
        }
        .frame(width: 1240, height: 880)
        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 1240, height: 880)))
    }
}
