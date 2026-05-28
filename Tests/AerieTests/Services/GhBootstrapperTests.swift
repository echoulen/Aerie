import XCTest
import Combine
@testable import Aerie

/// Step-through mock AuthService — returns canned responses in order, then
/// repeats the last value once the queue drains (used to verify polling stops
/// after `.ok`).
actor StepAuthService: AuthService {
    private var responses: [AuthBootstrapResult]
    private var tokens: [UUID: String] = [:]
    private(set) var bootstrapCalls = 0

    init(responses: [AuthBootstrapResult]) { self.responses = responses }

    func bootstrap() async throws -> AuthBootstrapResult {
        bootstrapCalls += 1
        guard !responses.isEmpty else { return .ghMissing }
        return responses.removeFirst()
    }
    func token(for accountId: UUID) -> String? { tokens[accountId] }
    func allAccounts() -> [GitHubAccount] { [] }

    func callCount() -> Int { bootstrapCalls }
}

final class GhBootstrapperTests: XCTestCase {
    func test_initialState_isNil() {
        let auth = StepAuthService(responses: [.ghMissing])
        let booter = GhBootstrapper(auth: auth, interval: 0.05)
        XCTAssertNil(booter.state.value)
    }

    func test_publishesGhMissing_thenNoAuth_thenOk() async throws {
        let auth = StepAuthService(responses: [.ghMissing, .noAuth, .ok(accounts: [])])
        let booter = GhBootstrapper(auth: auth, interval: 0.01)

        let exp = expectation(description: "saw three states")
        nonisolated(unsafe) var observed: [AuthBootstrapResult] = []
        let cancellable = booter.state
            .compactMap { $0 }
            .sink { result in
                observed.append(result)
                if observed.count == 3 { exp.fulfill() }
            }

        booter.start()
        await fulfillment(of: [exp], timeout: 2.0)
        cancellable.cancel()
        booter.stop()

        XCTAssertEqual(observed.count, 3)
        XCTAssertEqual(observed[0], .ghMissing)
        XCTAssertEqual(observed[1], .noAuth)
        if case .ok = observed[2] { /* ok */ } else { XCTFail("expected ok") }
    }

    func test_stopsPolling_afterOk() async throws {
        let auth = StepAuthService(responses: [.ghMissing, .ok(accounts: [])])
        let booter = GhBootstrapper(auth: auth, interval: 0.01)

        let exp = expectation(description: "saw ok")
        nonisolated(unsafe) var sawOk = false
        let cancellable = booter.state
            .compactMap { $0 }
            .sink { result in
                if case .ok = result, !sawOk {
                    sawOk = true
                    exp.fulfill()
                }
            }

        booter.start()
        await fulfillment(of: [exp], timeout: 2.0)

        // Snapshot the call count right after `.ok` was observed.
        let countAtOk = await auth.callCount()

        // Sleep well past the polling interval — if the loop kept running,
        // bootstrapCalls would grow.
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms vs 10ms interval

        let countAfterWait = await auth.callCount()
        cancellable.cancel()
        booter.stop()

        XCTAssertEqual(countAtOk, countAfterWait,
                       "bootstrap() should not be called again after .ok")
    }
}
