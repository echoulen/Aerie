import XCTest
@testable import Aerie

/// Guards the resource-bundle resolver used by `Backdrop` / `AboutScreen`.
///
/// The shipped `.app` crashed on launch because SwiftPM's generated
/// `Bundle.module` accessor only looks at `Bundle.main.bundleURL/Aerie_Aerie.bundle`
/// (the .app *root*, where a loose bundle breaks code signing) and a build-time
/// absolute path (absent on any other machine). `Bundle.aerieResources` instead
/// resolves the bundle from `Contents/Resources/` (where the Makefile copies it,
/// which is sign-safe), falling back to `.module` for `swift test` / dev.
final class BundleResourcesTests: XCTestCase {
    func test_aerieResources_resolvesBundleWithShippedResources() {
        let bundle = Bundle.aerieResources
        XCTAssertNotNil(
            bundle.url(forResource: "noise", withExtension: "png"),
            "noise.png must be loadable from the resolved resource bundle"
        )
        XCTAssertNotNil(
            bundle.url(forResource: "app-icon", withExtension: "png"),
            "app-icon.png must be loadable from the resolved resource bundle"
        )
    }
}
