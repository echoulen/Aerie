import XCTest
import SwiftUI
import Combine
import SnapshotTesting
@testable import Aerie

/// Stub `AuthService` that always returns the same canned `AuthBootstrapResult`.
private actor FixedAuthService: AuthService {
    let result: AuthBootstrapResult
    init(_ result: AuthBootstrapResult) { self.result = result }
    func bootstrap() async throws -> AuthBootstrapResult { result }
    func token(for accountId: UUID) -> String? { nil }
    func allAccounts() -> [GitHubAccount] { [] }
}

final class FirstRunRootTests: XCTestCase {
    private func waitForState(
        _ booter: GhBootstrapper,
        expected: AuthBootstrapResult
    ) async throws {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if let s = booter.state.value, s == expected { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("never reached state \(expected)")
    }

    func test_firstRunRoot_renderGhMissing() async throws {
        let auth = FixedAuthService(.ghMissing)
        let booter = GhBootstrapper(auth: auth, interval: 0.05)
        booter.start()
        try await waitForState(booter, expected: .ghMissing)

        // FirstRunRoot's content subscribes via Combine on the main runloop —
        // snapshotting the underlying body view directly (NoGhBody) avoids
        // the one-frame async dispatch that makes FirstRunRoot's first paint
        // flaky in a headless test host.
        await MainActor.run {
            let view = ZStack {
                Backdrop()
                NoGhBody(onRecheck: { booter.recheckNow() })
                    .glass(.card)
                    .padding(48)
            }
            .frame(width: 800, height: 600)

            let host = NSHostingView(rootView: view)
            assertSnapshot(of: host, as: .image(size: CGSize(width: 800, height: 600)))
        }

        booter.stop()
    }

    func test_firstRunRoot_renderNoAuth() async throws {
        let auth = FixedAuthService(.noAuth)
        let booter = GhBootstrapper(auth: auth, interval: 0.05)
        booter.start()
        try await waitForState(booter, expected: .noAuth)

        await MainActor.run {
            let view = ZStack {
                Backdrop()
                NoAuthBody(onRecheck: { booter.recheckNow() })
                    .glass(.card)
                    .padding(48)
            }
            .frame(width: 800, height: 600)

            let host = NSHostingView(rootView: view)
            assertSnapshot(of: host, as: .image(size: CGSize(width: 800, height: 600)))
        }

        booter.stop()
    }
}
