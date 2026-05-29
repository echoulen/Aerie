import Combine
import Foundation

extension Notification.Name {
    /// Posted (on the main actor) after a `PRSyncService` sync writes fresh PRs
    /// into `pr_cache`. The main window observes it to re-project the PRs tab.
    static let aeriePRCacheDidChange = Notification.Name("aerie.prCacheDidChange")
}

/// Process-wide singleton that owns the long-lived services and shares them
/// between the main window scene and the Settings window scene (SwiftUI's
/// `WindowGroup` + `Window` scenes don't share `@State`, so we hoist the
/// services here).
///
/// Polling orchestration is wired here: the scheduler's single per-repo refresh
/// closure drives BOTH `PRSyncService` (PRs tab) and `GitStatusRefresher`
/// (Repos tab) for each repo, and `startPolling()` follows app focus. The
/// remaining integration wiring (MCP consent gating, `.claude/.mcp.json`
/// upsert) is intentionally minimal — it covers what the shipped views need to
/// render without crashing, and can hook in here later without rippling through
/// every view.
@MainActor
final class AppServices {
    static let shared: AppServices = {
        do {
            return try AppServices()
        } catch {
            fatalError("Failed to initialize AppServices: \(error)")
        }
    }()

    let db: AppDatabase
    let auth: LiveAuthService
    let apiClient: LiveGitHubAPIClient
    let multiApi: MultiAccountAPI
    let prSync: PRSyncService
    let gitService: any GitService
    let scheduler: PollingScheduler
    let focusObserver: any AppFocusObserver
    let mcpRouter: JSONRPCRouter
    let mcpRegistry: MCPToolRegistry
    let mcpLogger: ActivityLogger
    let mcpServer: MCPServer
    let discovery: DiscoveryFileWriter
    let configWriter: ClaudeCodeConfigWriter

    /// Fires after each polling tick upserts fresh git status. The main shell
    /// subscribes (throttled) to re-read its `ReposViewModel` so the cards
    /// reflect the live branch / dirty state without a manual refresh.
    let gitStatusDidChange: PassthroughSubject<Void, Never>

    /// Retains the focus→scheduler subscription created by `startPolling()`.
    /// Held here (rather than in a view) because the polling lifecycle must
    /// outlive any single window. Also gates `startPolling()`'s idempotency.
    private var focusSubscription: AnyCancellable?

    private init() throws {
        let db = try AppDatabase(url: AppDatabase.defaultURL())
        // Pass the AccountDAO so bootstrap can reconcile discovered gh
        // accounts into the persistence layer — without this, the Settings ·
        // Accounts screen reads an empty table and always shows zero rows
        // even when `gh` is fully authenticated.
        let auth = LiveAuthService(accountStore: db.accounts)
        let client = LiveGitHubAPIClient()

        let tokensByAccount: @Sendable () async -> [UUID: String] = { [auth] in
            let accounts = await auth.allAccounts()
            var map: [UUID: String] = [:]
            for account in accounts {
                if let token = await auth.token(for: account.id) {
                    map[account.id] = token
                }
            }
            return map
        }
        let accountsInOrder: @Sendable () async -> [UUID] = { [auth] in
            await auth.allAccounts().map(\.id)
        }

        let multiApi = MultiAccountAPI(
            client: client,
            tokensByAccount: tokensByAccount,
            accountsInOrder: accountsInOrder
        )

        // Polling orchestration. The scheduler owns a SINGLE per-repo refresh
        // closure, so it must drive both sides for each repo:
        //   * PR fetch → cache: `prSync.sync` posts `.aeriePRCacheDidChange`
        //     (on main, via `onChange`) so the PRs tab re-projects.
        //   * Local git status: `refresher.refresh` upserts `gitStatusCache`,
        //     then we signal `gitStatusDidChange` (on main — `PassthroughSubject`
        //     `.send()` isn't thread-safe) so the Repos tab re-reads.
        // Both captured values are Sendable (actors / value types), so they're
        // safe inside the scheduler's `@Sendable` closure.
        let prSync = PRSyncService(db: db, api: multiApi, onChange: {
            await MainActor.run {
                NotificationCenter.default.post(name: .aeriePRCacheDidChange, object: nil)
            }
        })
        let gitService = LiveGitService()
        let refresher = GitStatusRefresher(db: db, gitService: gitService)
        let statusSubject = PassthroughSubject<Void, Never>()
        let scheduler = PollingScheduler(clock: LiveClock()) { [prSync, refresher, statusSubject] repoId in
            await prSync.sync(repoId: repoId)
            await refresher.refresh(repoId: repoId)
            await MainActor.run { statusSubject.send() }
        }
        let focusObserver = LiveAppFocusObserver()

        let router = JSONRPCRouter()
        let registry = MCPToolRegistry()
        let logger = ActivityLogger(db: db)
        let server = MCPServer(router: router, registry: registry, logger: logger)

        self.db = db
        self.auth = auth
        self.apiClient = client
        self.multiApi = multiApi
        self.prSync = prSync
        self.gitService = gitService
        self.scheduler = scheduler
        self.focusObserver = focusObserver
        self.gitStatusDidChange = statusSubject
        self.mcpRouter = router
        self.mcpRegistry = registry
        self.mcpLogger = logger
        self.mcpServer = server
        self.discovery = DiscoveryFileWriter()
        self.configWriter = ClaudeCodeConfigWriter()
    }

    /// Starts focus-driven polling: the scheduler runs while the app is active
    /// and pauses when it resigns. On the first `active` signal it ticks
    /// immediately (every repo is due), so the PRs and Repos tabs populate
    /// shortly after launch and stay fresh on the configured cadence. Idempotent
    /// — the main window calls it on appear, and repeat calls are no-ops.
    func startPolling() {
        guard focusSubscription == nil else { return }
        focusSubscription = scheduler.attachFocusObserver(focusObserver) { [db] in
            ((try? await db.repos.all()) ?? []).filter { !$0.hidden }.map(\.id)
        }

        // Apply the user's persisted cadences so the loop ticks at the
        // configured rate (not the 30/300 defaults) once past the first tick.
        Task { [scheduler, db] in
            let active = (try? await db.settings.getInt("polling.active_seconds")) ?? nil
            let background = (try? await db.settings.getInt("polling.background_seconds")) ?? nil
            await scheduler.setCadences(
                active: TimeInterval(active ?? 30),
                background: TimeInterval(background ?? 300)
            )
        }
    }
}
