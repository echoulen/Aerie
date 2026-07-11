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

    // MARK: Task 7.3 — rate-limit throttle

    func test_rateLimitThrottle_doublesCadences() async throws {
        let recorder = RefreshRecorder()
        let scheduler = PollingScheduler(clock: VirtualClock()) { id in
            await recorder.record(id)
        }
        let id = UUID()
        await scheduler.setActive(id)

        // Seed at t=1_700_000_000.
        let base = TimeInterval(1_700_000_000)
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base))
        let snap1 = await recorder.snapshot()
        XCTAssertEqual(snap1.count, 1)

        // Without throttle: active cadence is 30s, so +30 from seed is due.
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 30))
        let snap2 = await recorder.snapshot()
        XCTAssertEqual(snap2.count, 2)

        // Apply throttle (remaining < 500, reset in future).
        await scheduler.reportRateLimit(RateLimitSnapshot(
            remaining: 100,
            resetEpoch: base + 3600,
            limit: 5000
        ))

        // Cadence is now doubled to 60s. At +30 from last fetch, NOT due.
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 60))
        let snap3 = await recorder.snapshot()
        XCTAssertEqual(snap3.count, 2, "throttled cadence not yet elapsed")

        // At +60 from last fetch, due.
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 90))
        let snap4 = await recorder.snapshot()
        XCTAssertEqual(snap4.count, 3)

        // After reset epoch passes, throttle clears even if snapshot still present.
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 3700))
        let afterReset = await recorder.snapshot()
        XCTAssertGreaterThanOrEqual(afterReset.count, 4)
    }

    func test_rateLimitThrottle_clearsWhenRemainingRecovers() async throws {
        let recorder = RefreshRecorder()
        let scheduler = PollingScheduler(clock: VirtualClock()) { id in
            await recorder.record(id)
        }
        let id = UUID()
        await scheduler.setActive(id)

        let base = TimeInterval(1_700_000_000)
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base))

        // Throttle on.
        await scheduler.reportRateLimit(RateLimitSnapshot(
            remaining: 100,
            resetEpoch: base + 3600,
            limit: 5000
        ))
        // At +30, throttled cadence (60s) means NOT due.
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 30))
        let snap1 = await recorder.snapshot()
        XCTAssertEqual(snap1.count, 1)

        // Fresh snapshot says remaining recovered.
        await scheduler.reportRateLimit(RateLimitSnapshot(
            remaining: 4000,
            resetEpoch: base + 3600,
            limit: 5000
        ))
        // Cadence is back to 30s — at +30 from last fetch, due.
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 30))
        let snap2 = await recorder.snapshot()
        XCTAssertEqual(snap2.count, 2)
    }

    // MARK: App-focus cadence multiplier

    func test_setAppActive_false_quadruplesCadence() async throws {
        let recorder = RefreshRecorder()
        let scheduler = PollingScheduler(clock: VirtualClock()) { id in
            await recorder.record(id)
        }
        let id = UUID()
        await scheduler.setActive(id)

        let base = TimeInterval(1_700_000_000)
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base))
        let snap1 = await recorder.snapshot()
        XCTAssertEqual(snap1.count, 1)

        await scheduler.setAppActive(false)

        // Backgrounded: active cadence (30s) is now 4x = 120s. At +30, NOT due.
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 30))
        let snap2 = await recorder.snapshot()
        XCTAssertEqual(snap2.count, 1, "backgrounded cadence not yet elapsed")

        // At +120, due.
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 120))
        let snap3 = await recorder.snapshot()
        XCTAssertEqual(snap3.count, 2)

        // Foregrounded again: cadence back to 30s. At +30 from last fetch, due.
        await scheduler.setAppActive(true)
        await scheduler.tickOnce(repoIds: [id], now: Date(timeIntervalSince1970: base + 150))
        let snap4 = await recorder.snapshot()
        XCTAssertEqual(snap4.count, 3)
    }

    // MARK: Task 7.2 — bounded concurrency

    func test_refreshAll_capsConcurrencyToFive() async throws {
        actor Counter {
            private(set) var current = 0
            private(set) var peak = 0
            func enter() { current += 1; peak = max(peak, current) }
            func leave() { current -= 1 }
            func snapshotPeak() -> Int { peak }
        }
        let counter = Counter()
        let ids = (0..<50).map { _ in UUID() }
        let scheduler = PollingScheduler(
            clock: VirtualClock(),
            maxInFlight: 5
        ) { _ in
            await counter.enter()
            // ~5ms hold so contention is real and we actually hit the cap.
            try? await Task.sleep(nanoseconds: 5_000_000)
            await counter.leave()
        }
        // distantFuture ensures all 50 repos are due.
        await scheduler.tickOnce(repoIds: ids, now: Date.distantFuture)
        let peak = await counter.snapshotPeak()
        XCTAssertLessThanOrEqual(peak, 5)
        XCTAssertEqual(peak, 5, "should saturate the in-flight cap")
    }

    /// In production nothing ever designates an "active" repo — the main window
    /// shows every repo in one flat list, so `activeRepoId` stays nil. When it
    /// is nil, every repo must poll on the *active* cadence; otherwise the list
    /// you're looking at silently falls back to the 5-minute background cadence
    /// and only the manual Refresh button (which bypasses the gate) feels live.
    func test_tickOnce_withNoActiveRepo_usesActiveCadenceForAllRepos() async throws {
        let recorder = RefreshRecorder()
        let a = UUID()
        let b = UUID()
        let scheduler = PollingScheduler(clock: VirtualClock()) { i in
            await recorder.record(i)
        }
        // Deliberately never call setActive — mirrors production.

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        await scheduler.tickOnce(repoIds: [a, b], now: t0)
        let afterT0 = await recorder.snapshot()
        XCTAssertEqual(afterT0.count, 2, "both repos due on first tick")

        // At t0 + 29s (< active cadence 30): nothing new.
        await scheduler.tickOnce(repoIds: [a, b], now: t0.addingTimeInterval(29))
        let after29 = await recorder.snapshot()
        XCTAssertEqual(after29.count, 2, "no repo due before the active cadence")

        // At t0 + 30s: BOTH repos due on the active cadence — NOT stuck on the
        // 300s background cadence.
        await scheduler.tickOnce(repoIds: [a, b], now: t0.addingTimeInterval(30))
        let after30 = await recorder.snapshot()
        XCTAssertEqual(after30.count, 4,
                       "with no active repo, all repos refresh on the active cadence")
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
