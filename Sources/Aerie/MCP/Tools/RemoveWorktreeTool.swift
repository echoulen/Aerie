import Foundation

/// `aerie_remove_worktree` — write tool. `git worktree remove [--force] <path>`,
/// run from the main worktree. Validates the path belongs to the repo.
struct RemoveWorktreeTool: MCPTool {
    let name = "aerie_remove_worktree"
    let description = "Remove a repo worktree (git worktree remove)."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repo."),
            "worktree_path": JSONSchemaProperty(type: "string", description: "Path of the worktree to remove."),
            "force": JSONSchemaProperty(type: "boolean", description: "Remove even with uncommitted changes (default false)."),
        ],
        required: ["repo_id", "worktree_path"]
    )

    let db: AppDatabase
    let git: any GitService
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let (repo, worktree) = try await resolveWorktree(params: params, db: db, git: git)
        let force = boolParam(params, key: "force", default: false)
        do {
            try await git.removeWorktree(worktree, mainWorktreeAt: repo.localPath, force: force)
            Task { await refresh(repo.id) }
            return .object(["removed": .bool(true)])
        } catch {
            throw JSONRPCError(code: -32011, message: "Remove worktree failed: \(error)", data: nil)
        }
    }
}
