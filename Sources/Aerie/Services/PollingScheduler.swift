import Foundation

/// Heart of Aerie's polling pipeline. See spec §"Polling specifics".
///
/// The scheduler does not know anything about repos beyond their UUIDs. The
/// `refresh` closure passed in at construction time is the integration point
/// that knows how to fetch a given repo's data.
///
/// Determinism: the loop tick is broken into `tickOnce(repoIds:now:)`, which
/// tests can invoke directly without needing virtual clock plumbing. The live
/// loop (`start`/`stop`) wraps `tickOnce` and uses the injected `Clock` for
/// pacing.
actor PollingScheduler {
    // MARK: Configuration

    private let clock: any Clock
    private let refresh: @Sendable (UUID) async -> Void
    private let maxInFlight: Int

    private(set) var activeRepoId: UUID?
    private(set) var activeCadence: TimeInterval = 30
    private(set) var backgroundCadence: TimeInterval = 300
    private(set) var heartbeat: TimeInterval = 30

    // MARK: State

    private var fetchedAt: [UUID: Date] = [:]
    private var loopTask: Task<Void, Never>?

    /// Most recent rate-limit snapshot (the integration layer reports the
    /// worst-case account here). When `remaining < rateLimitThreshold` and we
    /// haven't reached `resetEpoch` yet, both cadences are doubled.
    private(set) var rateLimitThrottle: RateLimitSnapshot?

    private static let rateLimitThreshold = 500

    // MARK: Init

    init(
        clock: any Clock,
        maxInFlight: Int = 5,
        refresh: @escaping @Sendable (UUID) async -> Void
    ) {
        self.clock = clock
        self.maxInFlight = maxInFlight
        self.refresh = refresh
    }

    // MARK: Mutators

    func setActive(_ id: UUID?) { activeRepoId = id }

    func setCadences(active: TimeInterval, background: TimeInterval) {
        activeCadence = active
        backgroundCadence = background
    }

    func setHeartbeat(_ interval: TimeInterval) { heartbeat = interval }

    /// Called by the integration layer (Phase 8+) whenever a fresh rate-limit
    /// snapshot becomes available for the worst-case account (lowest remaining).
    /// Pass `nil` to clear any current throttle hint.
    func reportRateLimit(_ snapshot: RateLimitSnapshot?) {
        rateLimitThrottle = snapshot
    }

    // MARK: Loop control

    func start(repoIds: [UUID]) {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop(repoIds: repoIds)
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func isRunning() -> Bool { loopTask != nil }

    // MARK: Tick (test seam)

    /// One synchronous (per-actor) iteration of the loop. Used by both the
    /// running loop and tests; tests use it directly to avoid clock plumbing.
    func tickOnce(repoIds: [UUID], now: Date) async {
        let due = dueRepos(repoIds: repoIds, now: now)
        await refreshAll(due, now: now)
    }

    /// Forces an immediate refresh of every given repo, bypassing the per-repo
    /// cadence gate. Drives the same per-repo `refresh` closure as the loop, so
    /// it refreshes PRs, issues, and git status in one pass and resets each
    /// repo's cadence clock. Used by the header's manual Refresh button.
    func refreshNow(repoIds: [UUID], now: Date) async {
        await refreshAll(repoIds, now: now)
    }

    // MARK: Loop

    private func runLoop(repoIds: [UUID]) async {
        while !Task.isCancelled {
            let now = await clock.now()
            await tickOnce(repoIds: repoIds, now: now)
            let next = now.addingTimeInterval(heartbeat)
            do {
                try await clock.sleep(until: next)
            } catch {
                return
            }
        }
    }

    // MARK: Due-set + dispatch

    private func dueRepos(repoIds: [UUID], now: Date) -> [UUID] {
        let (active, background) = effectiveCadences(now: now)
        return repoIds.filter { id in
            let last = fetchedAt[id] ?? .distantPast
            let elapsed = now.timeIntervalSince(last)
            // When no repo is singled out as active (the production case — the
            // main window shows every repo in one flat list, so nothing calls
            // `setActive`), every repo uses the *active* cadence. Falling back to
            // `background` here would silently pin the whole list to the 5-minute
            // cadence and make auto-refresh feel broken next to the manual button.
            let isActive = (activeRepoId == nil) || (id == activeRepoId)
            let cadence = isActive ? active : background
            return elapsed >= cadence
        }
    }

    /// Applies the rate-limit throttle if a current snapshot says we are below
    /// the threshold and the reset epoch has not yet passed.
    private func effectiveCadences(now: Date) -> (active: TimeInterval, background: TimeInterval) {
        let throttled: Bool
        if let snap = rateLimitThrottle,
           snap.remaining < Self.rateLimitThreshold,
           now.timeIntervalSince1970 < snap.resetEpoch {
            throttled = true
        } else {
            throttled = false
        }
        let factor: TimeInterval = throttled ? 2 : 1
        return (activeCadence * factor, backgroundCadence * factor)
    }

    private func refreshAll(_ ids: [UUID], now: Date) async {
        guard !ids.isEmpty else { return }
        let cap = max(1, maxInFlight)
        let refresh = self.refresh   // capture sendable closure into local

        await withTaskGroup(of: UUID.self) { group in
            var iterator = ids.makeIterator()

            // Prime the pump up to the in-flight cap.
            var primed = 0
            while primed < cap, let id = iterator.next() {
                group.addTask {
                    await refresh(id)
                    return id
                }
                primed += 1
            }

            // Drain + refill: as each task finishes, mark fetchedAt and feed
            // the next id (if any) into the group.
            while let finishedId = await group.next() {
                fetchedAt[finishedId] = now
                if let next = iterator.next() {
                    group.addTask {
                        await refresh(next)
                        return next
                    }
                }
            }
        }
    }
}
