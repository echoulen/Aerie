import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

final class AboutScreenTests: XCTestCase {
    func test_aboutScreenSnapshot_seeded() {
        let view = AboutScreen(
            version: "0.1.0",
            buildSHA: "abc1234",
            githubURL: URL(string: "https://github.com/echoulen/Aerie")!
        )
        .frame(width: 820, height: 600)
        .background(AerieColor.backdrop1)
        assertSnapshot(of: NSHostingView(rootView: view),
                       as: .image(size: CGSize(width: 820, height: 600)))
    }
}
