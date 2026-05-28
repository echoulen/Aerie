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
    /// Subscribes to `observer.isActive`; starts the scheduler on `true`,
    /// stops it on `false`. The `repoIds` closure is invoked each time the app
    /// becomes active so callers can hand back the current list (the repo set
    /// can change while the app is backgrounded).
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
                if active {
                    let ids = await repoIds()
                    await self.start(repoIds: ids)
                } else {
                    await self.stop()
                }
            }
        }
    }
}
