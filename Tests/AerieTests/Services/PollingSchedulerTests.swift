import XCTest
@testable import Aerie

/// Test recorder that lets tests observe what UUIDs `refresh` was invoked with.
actor RefreshRecorder {
    private(set) var calls: [UUID] = []
    func record(_ id: UUID) { calls.append(id) }
    func snapshot() -> [UUID] { calls }
}

final class PollingSchedulerTests: XCTestCase {

    // MARK: Task 7.1 — tickOnce determinism

    func test_tickOnce_refreshesActiveAfterActiveCadence() async throws {
        let recorder = RefreshRecorder()
        let active = UUID()
        let other = UUID()
        let scheduler = PollingScheduler(clock: VirtualClock()) { id in
            await recorder.record(id)
        }
        await scheduler.setActive(active)

        // Seed both repos at t0; never-fetched repos are due immediately.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        await scheduler.tickOnce(repoIds: [active, other], now: t0)
        var calls = await recorder.snapshot()
        XCTAssertEqual(Set(calls), Set([active, other]))

        // At t0 + 29s (< activeCadence=30), nothing new.
        await scheduler.tickOnce(repoIds: [active, other], now: t0.addingTimeInterval(29))
        calls = await recorder.snapshot()
        XCTAssertEqual(calls.count, 2, "no new refreshes before any cadence elapses")

        // At t0 + 30s, active is due (background isn't, since bg=300).
        await scheduler.tickOnce(repoIds: [active, other], now: t0.addingTimeInterval(30))
        calls = await recorder.snapshot()
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls.last, active)
    }

    func test_tickOnce_refreshesNonActiveAfterBackgroundCadence() async throws {
        let recorder = RefreshRecorder()
        let active = UUID()
        let bg = UUID()
        let scheduler = PollingScheduler(clock: VirtualClock()) { id in
            await recorder.record(id)
        }
        await scheduler.setActive(active)

        // Initial tick: both are due (never fetched).
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        await scheduler.tickOnce(repoIds: [active, bg], now: t0)
        let afterT0 = await recorder.snapshot()
        XCTAssertEqual(afterT0.count, 2)

        // At t0 + 60 (active cadence elapsed twice over, but bg cadence not yet).
        await scheduler.tickOnce(repoIds: [active, bg], now: t0.addingTimeInterval(60))
        let after60 = await recorder.snapshot()
        XCTAssertEqual(after60.filter { $0 == active }.count, 2)
        XCTAssertEqual(after60.filter { $0 == bg }.count, 1, "bg not due yet at t=60")

        // At t0 + 300, bg is due.
        await scheduler.tickOnce(repoIds: [active, bg], now: t0.addingTimeInterval(300))
        let after300 = await recorder.snapshot()
        XCTAssertEqual(after300.filter { $0 == bg }.count, 2)
    }

    func test_tickOnce_doesNotRefreshBeforeCadence() async throws {
        let recorder = RefreshRecorder()
        let id = UUID()
        let scheduler = PollingScheduler(clock: VirtualClock()) { i in
            await recorder.record(i)
        }
        await scheduler.setActive(id)

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        await scheduler.tickOnce(repoIds: [id], now: t0)
        let first = await recorder.snapshot()
        XCTAssertEqual(first.count, 1)

        // Tick again 1s later: nothing new.
        await scheduler.tickOnce(repoIds: [id], now: t0.addingTimeInterval(1))
        let second = await recorder.snapshot()
        XCTAssertEqual(second.count, 1)

        // Tick again 29s later (< 30): still nothing.
        await scheduler.tickOnce(repoIds: [id], now: t0.addingTimeInterval(29))
        let third = await recorder.snapshot()
        XCTAssertEqual(third.count, 1)
    }

    func test_setActive_changesWhichRepoUsesActiveCadence() async throws {
        let recorder = RefreshRecorder()
        let a = UUID()
        let b = UUID()
        let scheduler = PollingScheduler(clock: VirtualClock()) { i in
            await recorder.record(i)
        }
        await scheduler.setActive(a)

        // Initial: both fire.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        await scheduler.tickOnce(repoIds: [a, b], now: t0)

        // Switch active to b.
        await scheduler.setActive(b)

        // At t0 + 30: only b should fire (active now, 30s cadence).
        // a is now background (300s), not due.
        await scheduler.tickOnce(repoIds: [a, b], now: t0.addingTimeInterval(30))
        let calls = await recorder.snapshot()
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls[2], b)
    }
}
