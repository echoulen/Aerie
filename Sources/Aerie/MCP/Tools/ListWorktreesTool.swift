import Foundation

/// `aerie_list_worktrees` — read-only, live enumeration of a repo's extra git
/// worktrees (the main checkout is filtered out by `git.worktrees`). Not
/// cached; `WorktreeRow` is not Codable, so the JSON is hand-built.
struct ListWorktreesTool: MCPTool {
    let name = "aerie_list_worktrees"
    let description = "List a repository's extra git worktrees (branch, dirty state, path)."
    let isWrite = false
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repository."),
        ],
        required: ["repo_id"]
    )

    let db: AppDatabase
    let git: any GitService

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        let rows = await git.worktrees(mainWorktreeAt: repo.localPath)
        let items: [JSONValue] = rows.map { wt in
            .object([
                "path": .string(wt.path.path),
                "branch_label": .string(wt.branchLabel),
                "is_detached": .bool(wt.isDetached),
                "is_dirty": .bool(wt.isDirty),
                "dirty_file_count": .int(wt.dirtyFileCount),
                "prunable": .bool(wt.prunable),
                "source": .string(wt.source == .superset ? "superset" : "manual"),
            ])
        }
        return .object(["worktrees": .array(items)])
    }
}
