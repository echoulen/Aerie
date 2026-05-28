import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class BackdropTests: XCTestCase {
    func test_backdropSnapshot() {
        let view = Backdrop().frame(width: 1240, height: 880)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 1240, height: 880)))
    }
}
