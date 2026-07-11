import XCTest
import Combine
@testable import Aerie

final class AppFocusObserverTests: XCTestCase {

    func test_stubObserver_publishesInitialActiveState() async throws {
        let stub = StubAppFocusObserver()
        let exp = expectation(description: "receives initial value")
        var received: [Bool] = []
        let cancellable = stub.isActive.sink { value in
            received.append(value)
            if received.count == 1 { exp.fulfill() }
        }
        await fulfillment(of: [exp], timeout: 1.0)
        cancellable.cancel()
        XCTAssertEqual(received, [true])
    }

    func test_attachFocusObserver_startsSchedulerOnActive() async throws {
        let recorder = RefreshRecorder()
        let scheduler = PollingScheduler(clock: VirtualClock()) { id in
            await recorder.record(id)
        }
        let stub = StubAppFocusObserver()
        let cancellable = scheduler.attachFocusObserver(stub, repoIds: { [] })

        // Drive observer twice (already-true initial value + a re-emission)
        // so the actor task has a clear chance to apply start().
        try await waitFor(timeout: 1.0) {
            await scheduler.isRunning()
        }
        cancellable.cancel()
        await scheduler.stop()
    }

    func test_attachFocusObserver_keepsRunningButSlowsCadenceOnInactive() async throws {
        let recorder = RefreshRecorder()
        let scheduler = PollingScheduler(clock: VirtualClock()) { id in
            await recorder.record(id)
        }
        let stub = StubAppFocusObserver()
        let cancellable = scheduler.attachFocusObserver(stub, repoIds: { [] })

        // Wait for start.
        try await waitFor(timeout: 1.0) {
            await scheduler.isRunning()
        }

        // Drive inactive.
        stub.subject.send(false)

        // The loop keeps running in the background — it no longer stops —
        // but the scheduler records that the app isn't frontmost so the
        // cadence gate (tested in PollingSchedulerTests) slows down.
        try await waitFor(timeout: 1.0) {
            await !scheduler.isAppActive
        }
        let stillRunning = await scheduler.isRunning()
        XCTAssertTrue(stillRunning, "polling should keep going in the background, just slower")
        cancellable.cancel()
        await scheduler.stop()
    }

    // MARK: - Polling helper

    private func waitFor(
        timeout: TimeInterval,
        _ predicate: @Sendable @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        XCTFail("waitFor timed out after \(timeout)s")
    }
}
