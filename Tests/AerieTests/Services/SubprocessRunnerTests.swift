import XCTest
@testable import Aerie

final class SubprocessRunnerTests: XCTestCase {
    func test_runsTrueAndReturnsExitZero() async throws {
        let runner = LiveSubprocessRunner()
        let (_, _, rc) = try await runner.run("true", [])
        XCTAssertEqual(rc, 0)
    }

    // MARK: - PATH augmentation
    //
    // A GUI app launched from Finder/LaunchServices inherits only the minimal
    // launchd PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), which omits Homebrew —
    // so `which gh` failed and Aerie wrongly showed "Install GitHub CLI".

    func test_augmentedPATH_prependsHomebrewAndKeepsExisting() {
        let parts = SubprocessPATH.augmented(base: "/usr/bin:/bin")
            .split(separator: ":").map(String.init)
        XCTAssertEqual(parts.first, "/opt/homebrew/bin", "Homebrew bin must come first")
        XCTAssertTrue(parts.contains("/usr/local/bin"), "Intel/other Homebrew prefix included")
        XCTAssertTrue(parts.contains("/usr/bin"), "existing entries preserved")
        XCTAssertTrue(parts.contains("/bin"))
        XCTAssertEqual(parts.count, Set(parts).count, "no duplicate entries")
    }

    func test_augmentedPATH_dedupesWhenAlreadyPresent() {
        let parts = SubprocessPATH.augmented(base: "/opt/homebrew/bin:/usr/bin")
            .split(separator: ":").map(String.init)
        XCTAssertEqual(parts.filter { $0 == "/opt/homebrew/bin" }.count, 1)
    }

    func test_augmentedPATH_emptyBaseStillHasHomebrewAndSystemDirs() {
        let parts = SubprocessPATH.augmented(base: "")
            .split(separator: ":").map(String.init)
        XCTAssertTrue(parts.contains("/opt/homebrew/bin"))
        XCTAssertTrue(parts.contains("/usr/bin"))
    }
}
