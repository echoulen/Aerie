import Foundation

/// Abstract clock — `LiveClock` for production, `VirtualClock` for tests.
///
/// `now()` is async to keep the live + virtual implementations under one
/// protocol surface. The live impl returns immediately; the virtual impl is
/// actor-isolated so callers must await it.
protocol Clock: Sendable {
    func now() async -> Date

    /// Suspends until `until`. If the clock is already past `until`, returns
    /// immediately. Throws on cancellation.
    func sleep(until: Date) async throws
}

// MARK: - Live

struct LiveClock: Clock {
    func now() async -> Date { Date() }

    func sleep(until: Date) async throws {
        let delta = until.timeIntervalSinceNow
        guard delta > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(delta * 1_000_000_000))
    }
}

// MARK: - Virtual (deterministic, advanceable)

actor VirtualClock: Clock {
    private var current: Date
    private var waiters: [(until: Date, cont: CheckedContinuation<Void, Error>)] = []

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    func now() -> Date { current }

    func sleep(until target: Date) async throws {
        if current >= target { return }
        try await withCheckedThrowingContinuation { cont in
            waiters.append((target, cont))
        }
    }

    /// Advances the virtual clock by `seconds` and wakes any waiter whose
    /// deadline is now in the past.
    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
        let ready = waiters.filter { $0.until <= current }
        waiters.removeAll { $0.until <= current }
        for w in ready { w.cont.resume() }
    }

    /// Sets the time to exactly `date`; only fires waiters at or before it.
    /// Time only moves forward.
    func set(to date: Date) {
        let delta = date.timeIntervalSince(current)
        if delta > 0 { advance(by: delta) }
    }
}
