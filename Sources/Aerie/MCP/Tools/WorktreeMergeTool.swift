import Foundation

/// `aerie_worktree_merge` — write tool. Local merge of origin/<default> into a
/// worktree (the rail's Merge button). Distinct from the server-side
/// `aerie_update_pr_branch`.
struct WorktreeMergeTool: MCPTool {
    let name = "aerie_worktree_merge"
    let description = "Merge origin/<default> into a repo worktree (local merge)."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repo."),
            "worktree_path": JSONSchemaProperty(type: "string", description: "Path of the worktree to merge into."),
        ],
        required: ["repo_id", "worktree_path"]
    )

    let db: AppDatabase
    let git: any GitService
    let accountToken: @Sendable (UUID) async -> String?
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let (repo, worktree) = try await resolveWorktree(params: params, db: db, git: git)
        do {
            let token = await accountToken(repo.primaryAccountId)
            try await git.updateBranchFromBase(
                repoAt: worktree, defaultBranch: repo.defaultBranch, token: token
            )
            Task { await refresh(repo.id) }
            return .object(["merged": .bool(true), "worktree_path": .string(worktree.path)])
        } catch {
            throw JSONRPCError(code: -32011, message: "Worktree merge failed: \(error)", data: nil)
        }
    }
}
