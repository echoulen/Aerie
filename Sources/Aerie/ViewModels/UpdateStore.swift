import Foundation
import Observation

/// Where the app sits in the "is there a newer Aerie?" cycle. `.installing` is
/// terminal from the app's point of view — the installer quits the process a
/// moment later, so there is no success state to come back to, only a failure
/// to launch it.
enum UpdatePhase: Equatable {
    case idle
    case available(current: String, latest: String)
    case installing
    case failed(String)
}

/// Owns update checking + installation for the whole app. Held by
/// ``AppServices`` (not a view) so the menu's "Check for Updates…" and the
/// titlebar pill read the same state, and so the periodic check outlives any
/// one window.
@MainActor
@Observable
final class UpdateStore {
    private(set) var phase: UpdatePhase = .idle

    private let check: () async -> UpdateOutcome
    private let install: () throws -> Void
    private let watchInstall: () async -> String?
    /// The offer that was being installed, restored when a failure is
    /// dismissed so the user can retry straight away.
    private var lastOffer: UpdatePhase?
    private var installWatch: Task<Void, Never>?
    private let canSelfUpdate: Bool
    private let recheckNanos: UInt64
    private let focusThrottle: TimeInterval
    private let now: () -> Date
    private var pollTask: Task<Void, Never>?
    /// When the last check *started*. Recorded before the await so two checks
    /// racing (launch + the focus signal that arrives with it) can't both run.
    private var lastCheckStartedAt: Date?

    init(
        check: @escaping () async -> UpdateOutcome = { await UpdateChecker().check() },
        install: @escaping () throws -> Void = { try AppUpdater.run() },
        watchInstall: @escaping () async -> String? = { await AppUpdater.waitForFailure() },
        canSelfUpdate: Bool = UpdateStore.isInstalledInApplications,
        recheckInterval: TimeInterval = 6 * 60 * 60,
        focusThrottle: TimeInterval = 30 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.check = check
        self.install = install
        self.watchInstall = watchInstall
        self.canSelfUpdate = canSelfUpdate
        self.recheckNanos = UInt64(recheckInterval * 1_000_000_000)
        self.focusThrottle = focusThrottle
        self.now = now
    }

    /// Whether this copy is the one `install.sh` would replace. The script
    /// targets `/Applications/Aerie.app` specifically, so a build running from
    /// anywhere else — a `make dev` bundle in the repo, a copy on the Desktop —
    /// must not offer to self-update: it would replace and relaunch a
    /// *different* app than the one you're looking at. This isn't hypothetical
    /// for dev builds: the Makefile stamps them with the latest git tag, so a
    /// checkout sitting behind a fresh release parses as out-of-date and would
    /// light the pill on every launch.
    nonisolated static var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path
            .hasPrefix("/Applications/")
    }

    /// Background check. Failures stay silent: they're nearly always a build
    /// whose version isn't a release tag (`make dev`) or a flaky network, and
    /// neither earns a permanent badge in the titlebar.
    func refresh() async {
        lastCheckStartedAt = now()
        apply(await check(), silentFailure: true)
    }

    /// Re-check because the app came back to the foreground. Throttled: the
    /// six-hour loop alone means a release published just after launch goes
    /// unnoticed for most of a working day, but every window switch shouldn't
    /// hit GitHub's (anonymous, rate-limited) API either.
    func refreshOnFocus() async {
        if let last = lastCheckStartedAt, now().timeIntervalSince(last) < focusThrottle { return }
        await refresh()
    }

    /// The menu's explicit "Check for Updates…". Surfaces failures (the user
    /// asked, so answer) and hands the outcome back so the caller can show its
    /// alert — the pill lights up from the same result.
    @discardableResult
    func checkNow() async -> UpdateOutcome {
        lastCheckStartedAt = now()
        let outcome = await check()
        apply(outcome, silentFailure: false)
        return outcome
    }

    /// Spawns the installer. Only valid from `.available`; the phase then stays
    /// `.installing` until the installer quits the app — or reports that it
    /// failed / timed out, which turns the pill into "Update failed".
    func startInstall() {
        guard case .available = phase else { return }
        lastOffer = phase
        phase = .installing
        do {
            try install()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        let watch = watchInstall
        installWatch?.cancel()
        installWatch = Task { [weak self] in
            guard let message = await watch(), !Task.isCancelled else { return }
            self?.installFailed(message)
        }
    }

    /// Whether the current `.failed` phase came from an install (so the alert
    /// can say "Update Failed" rather than "Couldn't Check for Updates").
    var failureIsInstall: Bool {
        if case .failed = phase { return lastOffer != nil }
        return false
    }

    private func installFailed(_ message: String) {
        guard phase == .installing else { return }
        phase = .failed(message)
    }

    /// Clears a failure. After a failed install the offer comes back so the
    /// update can be retried; a failed check just returns to idle.
    func dismissFailure() {
        guard case .failed = phase else { return }
        phase = lastOffer ?? .idle
        lastOffer = nil
    }

    /// Starts the periodic check loop (idempotent — repeat calls are no-ops).
    /// Checks once immediately so a release published while the app was closed
    /// shows up on launch, then every `recheckInterval` for the long-running
    /// sessions where the app is never relaunched.
    func startChecking() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let nanos = self?.recheckNanos else { return }
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    /// Applies a check result. A result that lands after the installer started
    /// is dropped — the app is seconds from quitting and the pill must not
    /// repaint.
    private func apply(_ outcome: UpdateOutcome, silentFailure: Bool) {
        guard phase != .installing else { return }
        lastOffer = nil
        switch outcome {
        case .updateAvailable(let current, let latest, _):
            // Not installable from here → stay quiet in the titlebar. The menu
            // still reports the outcome it got back, so its alert can send the
            // user to the release page instead.
            phase = canSelfUpdate ? .available(current: current, latest: latest) : .idle
        case .upToDate:
            phase = .idle
        case .failed(let message):
            phase = silentFailure ? .idle : .failed(message)
        }
    }
}
