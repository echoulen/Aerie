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

    func test_appearance_sitsBetweenMCPandAdvanced() {
        // The sidebar renders routes in `allCases` order, and the design
        // (chat: "MCP 與 Advanced 之間") puts Appearance between them.
        let order = SettingsRoute.allCases
        let mcp = order.firstIndex(of: .mcp)
        let appearance = order.firstIndex(of: .appearance)
        let advanced = order.firstIndex(of: .advanced)
        XCTAssertNotNil(appearance)
        XCTAssertEqual(appearance, mcp.map { $0 + 1 })
        XCTAssertEqual(advanced, appearance.map { $0 + 1 })
    }

    func test_appearance_hasDisplayNameAppearance() {
        XCTAssertEqual(SettingsRoute.appearance.displayName, "Appearance")
    }
}
