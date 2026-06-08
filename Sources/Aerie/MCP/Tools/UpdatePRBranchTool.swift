import Foundation

/// `aerie_update_pr_branch` — write tool. Server-side "Update branch": merges
/// the base into the PR head via GitHub, fixing a `BEHIND` PR without needing a
/// local checkout. Distinct from the local `aerie_worktree_merge`.
struct UpdatePRBranchTool: MCPTool {
    let name = "aerie_update_pr_branch"
    let description = "Bring a PR's branch up to date with its base (server-side Update branch)."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repo."),
            "number": JSONSchemaProperty(type: "integer", description: "PR number."),
        ],
        required: ["repo_id", "number"]
    )

    let db: AppDatabase
    let api: MultiAccountAPI
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        let num = try intParam(params, key: "number")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        do {
            try await api.updatePullRequestBranch(
                owner: repo.githubOwner, repo: repo.githubRepo, number: num
            )
            Task { await refresh(repoId) }
            return .object(["updated": .bool(true)])
        } catch let apiErr as GitHubAPIError {
            throw JSONRPCError(code: -32010, message: "Update branch failed: \(apiErr.message)", data: nil)
        } catch {
            throw JSONRPCError(code: -32010, message: "Update branch failed: \(error)", data: nil)
        }
    }
}
