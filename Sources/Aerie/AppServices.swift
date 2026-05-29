import Foundation

/// Process-wide singleton that owns the long-lived services and shares them
/// between the main window scene and the Settings window scene (SwiftUI's
/// `WindowGroup` + `Window` scenes don't share `@State`, so we hoist the
/// services here).
///
/// The integration-layer wiring (polling orchestration, MCP consent gating,
/// `.claude/.mcp.json` upsert) is intentionally minimal — it covers what the
/// shipped views need to render without crashing. The richer wiring tracked
/// in the plan's "Known issues" section can hook in here later without
/// rippling through every view.
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
    let scheduler: PollingScheduler
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

        // Stub refresh — proper polling orchestration is a Known Issue at
        // the end of the plan. The scheduler still ticks; the closure is
        // a no-op until the orchestration layer is wired.
        let scheduler = PollingScheduler(clock: LiveClock()) { _ in }

        let router = JSONRPCRouter()
        let registry = MCPToolRegistry()
        let logger = ActivityLogger(db: db)
        let server = MCPServer(router: router, registry: registry, logger: logger)

        self.db = db
        self.auth = auth
        self.apiClient = client
        self.multiApi = multiApi
        self.scheduler = scheduler
        self.mcpRouter = router
        self.mcpRegistry = registry
        self.mcpLogger = logger
        self.mcpServer = server
        self.discovery = DiscoveryFileWriter()
        self.configWriter = ClaudeCodeConfigWriter()
    }
}
