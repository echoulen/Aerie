import Foundation

/// Builds the concrete MCP tools from app dependencies and registers them in
/// a ``MCPToolRegistry``. Kept separate from `AppServices` so the full roster
/// can be exercised in isolation (e.g. assert every tool is present).
///
/// The tools were implemented in earlier phases but never wired into the live
/// server; this is the single place that constructs and registers them.
enum MCPToolset {
    /// Construct and register all seven tools.
    ///
    /// - `refresh`: invoked (detached) after a write tool mutates state so the
    ///   rest of the app re-syncs the affected repo.
    /// - `accountToken`: resolves a gh account id → its token, so write tools
    ///   that fetch (hard reset) authenticate as the repo's bound account
    ///   rather than gh's globally-active account.
    static func registerAll(
        into registry: MCPToolRegistry,
        db: AppDatabase,
        git: any GitService,
        api: MultiAccountAPI,
        refresh: @escaping @Sendable (UUID) async -> Void,
        accountToken: @escaping @Sendable (UUID) async -> String?
    ) async {
        // Read-only tools.
        await registry.register(ListReposTool(db: db))
        await registry.register(ListPRsTool(db: db))
        await registry.register(GetPRTool(db: db))
        await registry.register(GetLocalStatusTool(db: db))
        await registry.register(GetPRLocalStateTool(db: db))
        // Write tools.
        await registry.register(MergePRTool(db: db, api: api, refresh: refresh))
        await registry.register(
            HardResetTool(db: db, git: git, refresh: refresh, accountToken: accountToken)
        )
    }
}
