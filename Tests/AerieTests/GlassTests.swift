import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class GlassTests: XCTestCase {
    func test_cardGlassSnapshot() {
        let view = ZStack {
            AerieColor.backdrop1
            VStack { Text("Hello").foregroundStyle(AerieColor.text1) }
                .padding(40)
                .glass(.card)
                .padding(40)
        }
        .frame(width: 320, height: 200)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 320, height: 200)))
    }
}
