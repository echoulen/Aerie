import XCTest
@testable import Aerie

final class UpdateAlertContentTests: XCTestCase {
    private let url = URL(string: "https://github.com/echoulen/Aerie/releases/tag/v0.4.0")!

    func test_upToDate_hasOKButtonAndNoDownload() {
        let c = UpdateAlertContent(outcome: .upToDate(current: "0.3.1"))
        XCTAssertEqual(c.title, "You're up to date")
        XCTAssertTrue(c.informative.contains("0.3.1"))
        XCTAssertEqual(c.buttons, ["OK"])
        XCTAssertNil(c.downloadURL)
    }

    func test_updateAvailable_hasDownloadButtonVersionsAndFirstOpenHint() {
        let c = UpdateAlertContent(
            outcome: .updateAvailable(current: "0.3.1", latest: "0.4.0", url: url))
        XCTAssertEqual(c.title, "Update Available")
        XCTAssertTrue(c.informative.contains("0.4.0"))
        XCTAssertTrue(c.informative.contains("0.3.1"))
        // first-open guidance must be present (Gatekeeper workaround)
        XCTAssertTrue(c.informative.contains("right-click"))
        XCTAssertEqual(c.buttons, ["Download", "Later"])
        XCTAssertEqual(c.downloadURL, url)
    }

    func test_failed_carriesMessageAndNoDownload() {
        let c = UpdateAlertContent(outcome: .failed("GitHub returned HTTP 503."))
        XCTAssertEqual(c.title, "Couldn't Check for Updates")
        XCTAssertTrue(c.informative.contains("503"))
        XCTAssertEqual(c.buttons, ["OK"])
        XCTAssertNil(c.downloadURL)
    }

    /// A failed install is not a failed check — the alert must say so.
    func test_installFailed_isTitledAsAFailedUpdate() {
        let c = UpdateAlertContent(installFailure: "Couldn't download https://x")
        XCTAssertEqual(c.title, "Update Failed")
        XCTAssertTrue(c.informative.contains("Couldn't download"))
        XCTAssertTrue(c.informative.contains(AppUpdater.logPath))
        XCTAssertEqual(c.buttons, ["OK"])
        XCTAssertNil(c.downloadURL)
    }

    func test_store_distinguishesInstallFailuresFromCheckFailures() async {
        let url = self.url
        let installing = await MainActor.run {
            UpdateStore(check: { .updateAvailable(current: "0.3.1", latest: "0.4.0", url: url) },
                        install: {}, watchInstall: { "boom" })
        }
        await installing.refresh()
        await MainActor.run { installing.startInstall() }
        for _ in 0..<200 {
            if await MainActor.run(body: { installing.phase != .installing }) { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let installFailed = await MainActor.run { installing.failureIsInstall }
        XCTAssertTrue(installFailed)

        let checking = await MainActor.run { UpdateStore(check: { .failed("offline") }, install: {}) }
        await checking.checkNow()
        let checkFailed = await MainActor.run { checking.failureIsInstall }
        XCTAssertFalse(checkFailed)
    }
}
