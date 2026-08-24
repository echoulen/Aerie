import XCTest
@testable import Aerie

final class UpdatePillTests: XCTestCase {
    /// No news → no chrome. The titlebar stays empty rather than carrying a
    /// permanent "check for updates" control.
    func test_idle_rendersNothing() {
        XCTAssertNil(UpdatePill.label(for: .idle))
    }

    func test_available_namesTheVersionYouGet() {
        XCTAssertEqual(UpdatePill.label(for: .available(current: "0.3.1", latest: "0.4.0")),
                       "Update to 0.4.0")
    }

    func test_installing_and_failed_labels() {
        XCTAssertEqual(UpdatePill.label(for: .installing), "Updating…")
        XCTAssertEqual(UpdatePill.label(for: .failed("boom")), "Update failed")
    }
}
