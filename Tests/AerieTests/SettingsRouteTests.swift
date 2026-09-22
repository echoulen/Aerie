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

    func test_aiReview_andAppearance_sitBetweenAIModelAndAdvanced() {
        // The sidebar renders routes in `allCases` order (`settings.jsx`):
        // AI Model, AI Review, Appearance, Advanced.
        let order = SettingsRoute.allCases
        let aiModel = order.firstIndex(of: .aiModel)
        let aiReview = order.firstIndex(of: .aiReview)
        let appearance = order.firstIndex(of: .appearance)
        let advanced = order.firstIndex(of: .advanced)
        XCTAssertNotNil(aiReview)
        XCTAssertEqual(aiReview, aiModel.map { $0 + 1 })
        XCTAssertEqual(appearance, aiReview.map { $0 + 1 })
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
