import XCTest
@testable import Aerie

final class AppUpdaterTests: XCTestCase {
    func test_shellQuoted_wrapsInSingleQuotes() {
        XCTAssertEqual(AppUpdater.shellQuoted("/Applications/Aerie.app"),
                       "'/Applications/Aerie.app'")
    }

    func test_shellQuoted_survivesSpacesAndApostrophes() {
        XCTAssertEqual(AppUpdater.shellQuoted("/Users/carlos' apps/Aerie.app"),
                       "'/Users/carlos'\\'' apps/Aerie.app'")
    }

    /// The `nohup … &` shape is the whole point: the script quits Aerie as its
    /// first act, so it has to outlive the process that spawned it.
    func test_detachedCommand_backgroundsTheScriptAndRedirectsItsLog() {
        let cmd = AppUpdater.detachedCommand(script: "/tmp/install.sh", log: "/tmp/aerie-update.log")
        XCTAssertEqual(cmd, "nohup /bin/bash '/tmp/install.sh' > '/tmp/aerie-update.log' 2>&1 &")
    }

    func test_run_withoutABundledScript_reportsScriptMissing() {
        XCTAssertThrowsError(try AppUpdater.run(script: nil)) { error in
            XCTAssertEqual(error as? AppUpdater.Failure, .scriptMissing)
        }
    }
}
