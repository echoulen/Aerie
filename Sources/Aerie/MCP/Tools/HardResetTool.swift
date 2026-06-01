import Foundation

/// `aerie_hard_reset_to_default` — write tool. Destructively resets a
/// repository's working tree to `origin/<default_branch>` and returns a
/// summary of what was discarded.
///
/// Failure modes:
/// - Unknown `repo_id` → `-32602` (invalid params)
/// - Git operation failure (missing remote, libgit2 error, etc.) → `-32011`
struct HardResetTool: MCPTool {
    let name = "aerie_hard_reset_to_default"
    let description = "Hard reset a repository's working tree to origin/<default_branch>."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(
                type: "string",
                description: "UUID of the repo."
            ),
        ],
        required: ["repo_id"]
    )

    let db: AppDatabase
    let git: any GitService
    /// Invoked detached after a successful reset so the rest of the app
    /// can refresh its git/PR state. Tests pass a spy.
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        do {
            // token: nil — this tool has no AuthService dependency, so the fetch
            // uses gh's active account. Acceptable for now: the tool isn't wired
            // into the live MCP server. Thread the repo's bound-account token
            // here (like the app's reset path) if/when it ships.
            let summary = try await git.hardResetToOrigin(
                repoAt: repo.localPath,
                defaultBranch: repo.defaultBranch,
                token: nil
            )
            Task { await refresh(repoId) }
            return .object([
                "discarded_dirty_files": .int(summary.discardedDirtyFiles),
                "discarded_commits": .int(summary.discardedCommits),
            ])
        } catch {
            throw JSONRPCError(
                code: -32011,
                message: "Hard reset failed: \(error)",
                data: nil
            )
        }
    }
}
