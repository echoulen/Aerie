import Foundation

/// `aerie_worktree_discard` — write tool. Discards unstaged changes in a
/// worktree (`git restore .` + `git clean -fd`). Validates the path.
struct WorktreeDiscardTool: MCPTool {
    let name = "aerie_worktree_discard"
    let description = "Discard all unstaged changes in a repo worktree."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repo."),
            "worktree_path": JSONSchemaProperty(type: "string", description: "Path of the worktree to clean."),
        ],
        required: ["repo_id", "worktree_path"]
    )

    let db: AppDatabase
    let git: any GitService
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let (repo, worktree) = try await resolveWorktree(params: params, db: db, git: git)
        do {
            try await git.discardUnstaged(repoAt: worktree)
            Task { await refresh(repo.id) }
            return .object(["discarded": .bool(true)])
        } catch {
            throw JSONRPCError(code: -32011, message: "Worktree discard failed: \(error)", data: nil)
        }
    }
}
