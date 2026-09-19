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

    func test_appearance_sitsBetweenAIModelAndAdvanced() {
        // The sidebar renders routes in `allCases` order; Appearance sits just
        // above Advanced.
        let order = SettingsRoute.allCases
        let aiModel = order.firstIndex(of: .aiModel)
        let appearance = order.firstIndex(of: .appearance)
        let advanced = order.firstIndex(of: .advanced)
        XCTAssertNotNil(appearance)
        XCTAssertEqual(appearance, aiModel.map { $0 + 1 })
        XCTAssertEqual(advanced, appearance.map { $0 + 1 })
    }

    func test_appearance_hasDisplayNameAppearance() {
        XCTAssertEqual(SettingsRoute.appearance.displayName, "Appearance")
    }

    func test_aiModel_followsRepositories() {
        let order = SettingsRoute.allCases
        let repositories = order.firstIndex(of: .repositories)
        let aiModel = order.firstIndex(of: .aiModel)
        XCTAssertNotNil(aiModel)
        XCTAssertEqual(aiModel, repositories.map { $0 + 1 })
    }

    func test_aiModel_displayName() {
        XCTAssertEqual(SettingsRoute.aiModel.displayName, "AI Model")
    }
}
