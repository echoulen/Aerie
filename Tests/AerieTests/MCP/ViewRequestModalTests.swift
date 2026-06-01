import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class ViewRequestModalTests: XCTestCase {
    func test_viewRequestModal_snapshot() {
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"aerie_merge_pr","arguments":{"repo":"owner/repo","number":42}}}"#
        let response = #"{"jsonrpc":"2.0","id":1,"result":{"ok":true,"merged_at":"2026-05-29T01:23:45Z"}}"#
        let view = ZStack {
            Backdrop()
            ViewRequestModal(
                requestJSON: request,
                responseJSON: response,
                onClose: { }
            )
        }
        .frame(width: 1240, height: 880)
        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 1240, height: 880)))
    }
}
