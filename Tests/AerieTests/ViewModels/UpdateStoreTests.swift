import XCTest
@testable import Aerie

@MainActor
final class UpdateStoreTests: XCTestCase {
    private let releaseURL = URL(string: "https://github.com/echoulen/Aerie/releases/tag/v0.4.0")!

    private func makeStore(
        outcome: UpdateOutcome,
        install: @escaping () throws -> Void = {},
        canSelfUpdate: Bool = true
    ) -> UpdateStore {
        UpdateStore(check: { outcome }, install: install, canSelfUpdate: canSelfUpdate)
    }

    func test_refresh_newerRelease_offersTheUpdate() async {
        let store = makeStore(outcome: .updateAvailable(current: "0.3.1", latest: "0.4.0", url: releaseURL))
        await store.refresh()
        XCTAssertEqual(store.phase, .available(current: "0.3.1", latest: "0.4.0"))
    }

    func test_refresh_upToDate_staysIdle() async {
        let store = makeStore(outcome: .upToDate(current: "0.4.0"))
        await store.refresh()
        XCTAssertEqual(store.phase, .idle)
    }

    /// A background check that fails is almost always a build whose version
    /// isn't a release tag (`make dev`) or a flaky network — neither earns a
    /// permanent badge in the titlebar.
    func test_refresh_failure_staysSilent() async {
        let store = makeStore(outcome: .failed("offline"))
        await store.refresh()
        XCTAssertEqual(store.phase, .idle)
    }

    /// The menu's explicit check is the opposite: the user asked, so tell them.
    func test_checkNow_failure_surfacesTheError() async {
        let store = makeStore(outcome: .failed("offline"))
        let outcome = await store.checkNow()
        XCTAssertEqual(outcome, .failed("offline"))
        XCTAssertEqual(store.phase, .failed("offline"))
    }

    func test_refresh_clearsAPreviousFailure() async {
        let store = makeStore(outcome: .failed("offline"))
        await store.checkNow()
        XCTAssertEqual(store.phase, .failed("offline"))

        let recovered = UpdateStore(check: { .upToDate(current: "0.4.0") }, install: {})
        await recovered.refresh()
        XCTAssertEqual(recovered.phase, .idle)
    }

    func test_startInstall_runsTheInstallerAndStaysInstalling() async {
        var ran = 0
        let store = makeStore(
            outcome: .updateAvailable(current: "0.3.1", latest: "0.4.0", url: releaseURL),
            install: { ran += 1 }
        )
        await store.refresh()
        store.startInstall()
        XCTAssertEqual(ran, 1)
        XCTAssertEqual(store.phase, .installing)
    }

    func test_startInstall_ignoredWhenNoUpdateIsOffered() async {
        var ran = 0
        let store = makeStore(outcome: .upToDate(current: "0.4.0"), install: { ran += 1 })
        await store.refresh()
        store.startInstall()
        XCTAssertEqual(ran, 0)
        XCTAssertEqual(store.phase, .idle)
    }

    func test_startInstall_launchFailure_surfacesTheError() async {
        let store = makeStore(
            outcome: .updateAvailable(current: "0.3.1", latest: "0.4.0", url: releaseURL),
            install: { throw AppUpdater.Failure.scriptMissing }
        )
        await store.refresh()
        store.startInstall()
        guard case .failed = store.phase else {
            return XCTFail("expected .failed, got \(store.phase)")
        }
    }

    /// Once the installer is spawned the app is seconds from being quit — a
    /// check landing in that window must not repaint the pill.
    func test_refresh_whileInstalling_isIgnored() async {
        let store = makeStore(outcome: .updateAvailable(current: "0.3.1", latest: "0.4.0", url: releaseURL))
        await store.refresh()
        store.startInstall()
        await store.refresh()
        XCTAssertEqual(store.phase, .installing)
    }

    /// `install.sh` replaces `/Applications/Aerie.app`, so a build running from
    /// anywhere else (a `make dev` bundle in the repo, a copy on the Desktop)
    /// must not offer to update — it would replace a different app than the one
    /// on screen.
    func test_refresh_whenNotInstalledInApplications_staysSilent() async {
        let store = makeStore(
            outcome: .updateAvailable(current: "0.1.0", latest: "0.6.0", url: releaseURL),
            canSelfUpdate: false
        )
        await store.refresh()
        XCTAssertEqual(store.phase, .idle)
    }

    /// The menu still answers honestly for those builds — it just routes to the
    /// alert's Download button (the browser) instead of the in-app installer.
    func test_checkNow_whenNotInstalled_reportsTheUpdateWithoutOfferingToInstall() async {
        let store = makeStore(
            outcome: .updateAvailable(current: "0.1.0", latest: "0.6.0", url: releaseURL),
            canSelfUpdate: false
        )
        let outcome = await store.checkNow()
        XCTAssertEqual(outcome, .updateAvailable(current: "0.1.0", latest: "0.6.0", url: releaseURL))
        XCTAssertEqual(store.phase, .idle)
    }

    // MARK: - Focus-driven re-checks

    /// Coming back to the app shouldn't hit GitHub every time — bouncing
    /// between windows would hammer the (anonymous, rate-limited) API.
    func test_refreshOnFocus_skipsWhenCheckedRecently() async {
        var checks = 0
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = UpdateStore(
            check: { checks += 1; return .upToDate(current: "0.6.1") },
            install: {},
            canSelfUpdate: true,
            focusThrottle: 1_800,
            now: { clock }
        )
        await store.refreshOnFocus()
        clock.addTimeInterval(60)
        await store.refreshOnFocus()
        XCTAssertEqual(checks, 1)
    }

    func test_refreshOnFocus_checksAgainOnceTheThrottleWindowPasses() async {
        var checks = 0
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = UpdateStore(
            check: { checks += 1; return .upToDate(current: "0.6.1") },
            install: {},
            canSelfUpdate: true,
            focusThrottle: 1_800,
            now: { clock }
        )
        await store.refreshOnFocus()
        clock.addTimeInterval(1_801)
        await store.refreshOnFocus()
        XCTAssertEqual(checks, 2)
    }

    /// The throttle is advisory for focus only — the user clicking "Check for
    /// Updates…" always gets a real check.
    func test_checkNow_ignoresTheThrottle() async {
        var checks = 0
        let clock = Date(timeIntervalSince1970: 1_000)
        let store = UpdateStore(
            check: { checks += 1; return .upToDate(current: "0.6.1") },
            install: {},
            canSelfUpdate: true,
            focusThrottle: 1_800,
            now: { clock }
        )
        await store.refreshOnFocus()
        await store.checkNow()
        XCTAssertEqual(checks, 2)
    }

    func test_dismissFailure_returnsToIdle() async {
        let store = makeStore(outcome: .failed("offline"))
        await store.checkNow()
        store.dismissFailure()
        XCTAssertEqual(store.phase, .idle)
    }
}
