import XCTest
@testable import Aerie

final class SmokeTests: XCTestCase {
    func test_appBuilds() {
        // Existence of @main entry compiles is the smoke check.
        XCTAssertTrue(true)
    }
}
