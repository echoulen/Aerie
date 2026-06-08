import Foundation

/// `aerie_cleanup_merged_branch` — write tool. Resets the repo to
/// origin/<default> and deletes the *detected* already-merged branch (from
/// `mergedBranchCache`). Takes no `branch` param, so it can only ever delete a
/// branch Aerie has confirmed merged — never an arbitrary one.
struct CleanupMergedBranchTool: MCPTool {
    let name = "aerie_cleanup_merged_branch"
    let description = "Reset to default and delete the repo's detected already-merged branch."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repo."),
        ],
        required: ["repo_id"]
    )

    let db: AppDatabase
    let git: any GitService
    let accountToken: @Sendable (UUID) async -> String?
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        guard let info = try await db.mergedBranchCache.info(forRepo: repoId) else {
            throw JSONRPCError(code: -32011, message: "No merged branch detected for this repo", data: nil)
        }
        do {
            let token = await accountToken(repo.primaryAccountId)
            let summary = try await git.hardResetToOrigin(
                repoAt: repo.localPath, defaultBranch: repo.defaultBranch, token: token
            )
            try await git.deleteLocalBranch(repoAt: repo.localPath, branch: info.branch)
            Task { await refresh(repoId) }
            return .object([
                "discarded_dirty_files": .int(summary.discardedDirtyFiles),
                "discarded_commits": .int(summary.discardedCommits),
                "deleted_branch": .string(info.branch),
            ])
        } catch {
            throw JSONRPCError(code: -32011, message: "Cleanup failed: \(error)", data: nil)
        }
    }
}
