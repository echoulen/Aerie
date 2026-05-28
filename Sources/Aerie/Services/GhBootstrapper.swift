import Foundation
import Combine

/// Polls ``AuthService/bootstrap()`` every `interval` seconds and publishes the
/// current ``AuthBootstrapResult`` via a Combine ``CurrentValueSubject``.
/// Stops polling once `.ok` is observed (no reason to keep hitting `gh`).
final class GhBootstrapper: @unchecked Sendable {
    /// Latest observed result. `nil` means we haven't completed the first call yet.
    let state: CurrentValueSubject<AuthBootstrapResult?, Never> = .init(nil)

    private let auth: any AuthService
    private let interval: TimeInterval
    private var pollerTask: Task<Void, Never>?
    private let lock = NSLock()

    init(auth: any AuthService, interval: TimeInterval = 5.0) {
        self.auth = auth
        self.interval = interval
    }

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard pollerTask == nil else { return }
        pollerTask = Task { [weak self] in
            await self?.loop()
        }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        pollerTask?.cancel()
        pollerTask = nil
    }

    /// Force an immediate re-check by restarting the polling loop.
    func recheckNow() {
        stop()
        start()
    }

    private func loop() async {
        while !Task.isCancelled {
            let result = (try? await auth.bootstrap()) ?? .ghMissing
            state.send(result)
            if case .ok = result { return }   // success terminates the loop
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
        }
    }
}
