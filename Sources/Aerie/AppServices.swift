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
/// PR polling orchestration is wired here: the scheduler's per-repo refresh
/// closure drives `PRSyncService`, and `startPolling()` follows app focus. The
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
    let scheduler: PollingScheduler
    let focusObserver: any AppFocusObserver
    /// Retains the focus→scheduler subscription created by `startPolling()`.
    /// Held here (rather than in a view) because the polling lifecycle must
    /// outlive any single window.
    private var focusSubscription: AnyCancellable?
    let mcpRouter: JSONRPCRouter
    let mcpRegistry: MCPToolRegistry
    let mcpLogger: ActivityLogger
    let mcpServer: MCPServer
    let discovery: DiscoveryFileWriter
    let configWriter: ClaudeCodeConfigWriter

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

        // PR fetch → cache orchestration. The scheduler's per-repo refresh
        // closure drives `prSync.sync`; on a successful sync `onChange` posts
        // `.aeriePRCacheDidChange` (on main) so the PRs tab re-projects.
        let prSync = PRSyncService(db: db, api: multiApi, onChange: {
            await MainActor.run {
                NotificationCenter.default.post(name: .aeriePRCacheDidChange, object: nil)
            }
        })
        let scheduler = PollingScheduler(clock: LiveClock()) { repoId in
            await prSync.sync(repoId: repoId)
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
        self.scheduler = scheduler
        self.focusObserver = focusObserver
        self.mcpRouter = router
        self.mcpRegistry = registry
        self.mcpLogger = logger
        self.mcpServer = server
        self.discovery = DiscoveryFileWriter()
        self.configWriter = ClaudeCodeConfigWriter()
    }

    /// Starts focus-driven polling: the scheduler runs while the app is active
    /// and pauses when it resigns. On the first `active` signal it ticks
    /// immediately (every repo is due), so PRs appear shortly after launch and
    /// stay fresh on the configured cadence. Idempotent — the main window calls
    /// it on appear, and repeat calls are no-ops.
    func startPolling() {
        guard focusSubscription == nil else { return }
        focusSubscription = scheduler.attachFocusObserver(focusObserver) { [db] in
            ((try? await db.repos.all()) ?? []).filter { !$0.hidden }.map(\.id)
        }
    }
}
