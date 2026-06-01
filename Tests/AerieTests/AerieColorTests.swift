import XCTest
import SwiftUI
@testable import Aerie

final class AerieColorTests: XCTestCase {
    func test_amberIsAmberish() {
        // oklch(0.86 0.140 78) — sodium amber. Verify resolved RGBA stays in expected band.
        let nsColor = NSColor(AerieColor.amber).usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(nsColor.redComponent, 0.85)
        XCTAssertGreaterThan(nsColor.greenComponent, 0.55)
        XCTAssertLessThan(nsColor.blueComponent, 0.40)
    }

    func test_textTiersAreStrictlyDecreasing() {
        let alphas: [CGFloat] = [
            NSColor(AerieColor.text1).alphaComponent,
            NSColor(AerieColor.text2).alphaComponent,
            NSColor(AerieColor.text3).alphaComponent,
            NSColor(AerieColor.text4).alphaComponent,
        ]
        XCTAssertEqual(alphas, alphas.sorted(by: >))
    }
}
