import Foundation

/// Builds the concrete MCP tools from app dependencies and registers them in a
/// ``MCPToolRegistry``. Kept separate from `AppServices` so the full roster can
/// be exercised in isolation (e.g. assert every tool is present).
enum MCPToolset {
    /// Construct and register every tool.
    ///
    /// - `accounts`: resolves the connected gh accounts, used by `approve` to
    ///   pick an eligible (non-author) approver.
    /// - `refresh`: invoked (detached) after a write tool mutates state so the
    ///   rest of the app re-syncs the affected repo.
    /// - `accountToken`: resolves a gh account id → its token, so tools that
    ///   fetch (hard reset, force checkout, cleanup, worktree merge)
    ///   authenticate as the repo's bound account rather than gh's active one.
    static func registerAll(
        into registry: MCPToolRegistry,
        db: AppDatabase,
        git: any GitService,
        api: MultiAccountAPI,
        accounts: @escaping @Sendable () async -> [GitHubAccount],
        refresh: @escaping @Sendable (UUID) async -> Void,
        accountToken: @escaping @Sendable (UUID) async -> String?
    ) async {
        // Read-only tools.
        await registry.register(ListReposTool(db: db))
        await registry.register(ListPRsTool(db: db))
        await registry.register(GetPRTool(db: db))
        await registry.register(GetLocalStatusTool(db: db))
        await registry.register(GetPRLocalStateTool(db: db))
        await registry.register(ListIssuesTool(db: db))
        await registry.register(ListMergedBranchesTool(db: db))
        await registry.register(ListWorktreesTool(db: db, git: git))
        await registry.register(GetPRDiffTool(db: db, api: api))
        // Write tools.
        await registry.register(MergePRTool(db: db, api: api, refresh: refresh))
        await registry.register(
            HardResetTool(db: db, git: git, refresh: refresh, accountToken: accountToken)
        )
        await registry.register(ApprovePRTool(db: db, api: api, accounts: accounts, refresh: refresh))
        await registry.register(UpdatePRBranchTool(db: db, api: api, refresh: refresh))
        await registry.register(
            ForceCheckoutTool(db: db, git: git, accountToken: accountToken, refresh: refresh)
        )
        await registry.register(DiscardUnstagedTool(db: db, git: git, refresh: refresh))
        await registry.register(
            CleanupMergedBranchTool(db: db, git: git, accountToken: accountToken, refresh: refresh)
        )
        await registry.register(
            WorktreeMergeTool(db: db, git: git, accountToken: accountToken, refresh: refresh)
        )
        await registry.register(RemoveWorktreeTool(db: db, git: git, refresh: refresh))
        await registry.register(WorktreeDiscardTool(db: db, git: git, refresh: refresh))
    }
}
