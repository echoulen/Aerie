import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// Publishes the app's focus state — `true` when active, `false` when in
/// background. The integration layer wires this into `PollingScheduler` so the
/// polling loop pauses while the user is doing something else.
protocol AppFocusObserver: Sendable {
    var isActive: AnyPublisher<Bool, Never> { get }
}

// MARK: - Live (NSApplication-backed)

#if canImport(AppKit)
final class LiveAppFocusObserver: AppFocusObserver, @unchecked Sendable {
    private let subject = CurrentValueSubject<Bool, Never>(true)
    private var cancellables: Set<AnyCancellable> = []

    var isActive: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }

    init() {
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .map { _ in true }
            .subscribe(subject)
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: NSApplication.didResignActiveNotification)
            .map { _ in false }
            .subscribe(subject)
            .store(in: &cancellables)
    }
}
#endif

// MARK: - Stub (tests + previews)

/// Test/preview-friendly observer whose subject is publicly mutable, so callers
/// can drive arbitrary active/inactive transitions.
final class StubAppFocusObserver: AppFocusObserver, @unchecked Sendable {
    let subject = CurrentValueSubject<Bool, Never>(true)
    var isActive: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }
}

// MARK: - PollingScheduler glue

extension PollingScheduler {
    /// Subscribes to `observer.isActive` and keeps the scheduler's cadence in
    /// sync with app focus. The loop itself is never stopped by a focus
    /// change — it keeps polling in the background, just at
    /// `backgroundAppCadenceMultiplier`x the normal cadence, so PRs/Issues
    /// stay reasonably fresh for an unattended window instead of going
    /// stale until the user clicks back in.
    ///
    /// On each `true` (foreground) signal the loop is restarted with a fresh
    /// `repoIds` snapshot — this both ticks immediately (so returning to the
    /// app feels live) and picks up any repo added/removed while backgrounded
    /// (e.g. via an MCP tool call).
    ///
    /// Returns an `AnyCancellable` so callers can detach the subscription —
    /// keep it alive for as long as the scheduler should follow focus.
    nonisolated func attachFocusObserver(
        _ observer: any AppFocusObserver,
        repoIds: @escaping @Sendable () async -> [UUID]
    ) -> AnyCancellable {
        observer.isActive.sink { [weak self] active in
            Task { [weak self] in
                guard let self else { return }
                await self.setAppActive(active)
                guard active else { return }
                await self.stop()
                let ids = await repoIds()
                await self.start(repoIds: ids)
            }
        }
    }
}
