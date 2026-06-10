import Foundation
import Observation

/// One row in the Settings → Advanced "Rate limit" list. Pairs an account
/// with its most recently observed `RateLimitSnapshot`, or `nil` if no
/// snapshot exists yet (the account hasn't been used to make a call).
struct AccountRateLimitSnapshot: Equatable, Identifiable {
    var id: UUID { account.id }
    let account: GitHubAccount
    let snapshot: RateLimitSnapshot?
}

/// View model for the Settings → Advanced screen.
///
/// Persists the four user-controlled knobs (`polling.active_seconds`,
/// `polling.background_seconds`, `behavior.refresh_on_focus`,
/// `behavior.pause_on_blur`) via `SettingsDAO` and notifies the
/// `PollingScheduler` of cadence changes through an injected closure.
///
/// Dependencies are passed as closures (cadence applier, rate-limit
/// lookup, accounts provider) so tests don't need a live
/// `PollingScheduler` / `MultiAccountAPI` to exercise the VM. Same
/// pattern as `AccountsViewModel` (Phase 12).
@MainActor
@Observable
final class AdvancedViewModel {
    private(set) var activeCadence: TimeInterval = 30
    private(set) var backgroundCadence: TimeInterval = 300
    private(set) var refreshOnFocus: Bool = true
    private(set) var pauseOnBlur: Bool = true
    private(set) var rateLimits: [AccountRateLimitSnapshot] = []
    private(set) var error: String?

    static let defaultActive: TimeInterval = 30
    static let defaultBackground: TimeInterval = 300

    private let db: AppDatabase
    private let cadenceApplier: (TimeInterval, TimeInterval) async -> Void
    private let rateLimitProvider: (UUID) async -> RateLimitSnapshot?
    private let accountsProvider: () async throws -> [GitHubAccount]

    init(
        db: AppDatabase,
        cadenceApplier: @escaping (TimeInterval, TimeInterval) async -> Void,
        rateLimitProvider: @escaping (UUID) async -> RateLimitSnapshot?,
        accountsProvider: (() async throws -> [GitHubAccount])? = nil
    ) {
        self.db = db
        self.cadenceApplier = cadenceApplier
        self.rateLimitProvider = rateLimitProvider
        self.accountsProvider = accountsProvider ?? { try await db.accounts.all() }
    }

    /// Re-loads cadences + behavior toggles from `SettingsDAO`, then asks
    /// the rate-limit provider for a snapshot per account. On any throw,
    /// populates `error` and leaves previous state in place so the UI
    /// doesn't blank out on a transient failure.
    func refresh() async {
        do {
            // Cadences
            if let a = try await db.settings.getInt("polling.active_seconds") {
                activeCadence = TimeInterval(a)
            }
            if let b = try await db.settings.getInt("polling.background_seconds") {
                backgroundCadence = TimeInterval(b)
            }
            // Behavior
            if let r = try await db.settings.getBool("behavior.refresh_on_focus") {
                refreshOnFocus = r
            }
            if let p = try await db.settings.getBool("behavior.pause_on_blur") {
                pauseOnBlur = p
            }
            // Rate limits (per account)
            let accounts = try await accountsProvider()
            var snaps: [AccountRateLimitSnapshot] = []
            for acc in accounts {
                let snap = await rateLimitProvider(acc.id)
                snaps.append(AccountRateLimitSnapshot(account: acc, snapshot: snap))
            }
            rateLimits = snaps
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setActiveCadence(_ seconds: TimeInterval) async {
        activeCadence = max(5, seconds)
        try? await db.settings.setInt("polling.active_seconds", Int(activeCadence))
        await cadenceApplier(activeCadence, backgroundCadence)
    }

    func setBackgroundCadence(_ seconds: TimeInterval) async {
        backgroundCadence = max(activeCadence, seconds)
        try? await db.settings.setInt("polling.background_seconds", Int(backgroundCadence))
        await cadenceApplier(activeCadence, backgroundCadence)
    }

    func setRefreshOnFocus(_ value: Bool) async {
        refreshOnFocus = value
        try? await db.settings.setBool("behavior.refresh_on_focus", value)
    }

    func setPauseOnBlur(_ value: Bool) async {
        pauseOnBlur = value
        try? await db.settings.setBool("behavior.pause_on_blur", value)
    }

    func resetToDefaults() async {
        activeCadence = Self.defaultActive
        backgroundCadence = Self.defaultBackground
        refreshOnFocus = true
        pauseOnBlur = true
        try? await db.settings.setInt("polling.active_seconds", Int(Self.defaultActive))
        try? await db.settings.setInt("polling.background_seconds", Int(Self.defaultBackground))
        try? await db.settings.setBool("behavior.refresh_on_focus", true)
        try? await db.settings.setBool("behavior.pause_on_blur", true)
        await cadenceApplier(activeCadence, backgroundCadence)
    }
}
