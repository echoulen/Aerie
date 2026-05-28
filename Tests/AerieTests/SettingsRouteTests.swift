import XCTest
@testable import Aerie

final class SettingsRouteTests: XCTestCase {
    func test_allCases_haveDisplayName() {
        for route in SettingsRoute.allCases {
            XCTAssertFalse(route.displayName.isEmpty)
            XCTAssertFalse(route.systemIcon.isEmpty)
        }
    }

    func test_rawValueRoundTrip() {
        for route in SettingsRoute.allCases {
            XCTAssertEqual(SettingsRoute(rawValue: route.rawValue), route)
        }
    }
}
