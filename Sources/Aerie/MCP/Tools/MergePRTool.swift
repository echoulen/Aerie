import Foundation

/// `aerie_merge_pr` — write tool. Squash-merges a PR via the GitHub API
/// and (best-effort) kicks the polling pipeline so the UI catches up.
///
/// Failure modes:
/// - Unknown `repo_id` → `-32602` (invalid params)
/// - Missing `number` → `-32602` (invalid params)
/// - GitHub API error (4xx/5xx/network) → `-32010` (application error)
struct MergePRTool: MCPTool {
    let name = "aerie_merge_pr"
    let description = "Squash-merge a PR via the GitHub API."
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
    /// Invoked detached after a successful merge so the rest of the app
    /// (polling scheduler / view models) can refresh state. Phase 21 wires
    /// this to the live refresh path; tests pass a spy.
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        let num = try intParam(params, key: "number")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        do {
            let result = try await api.mergePR(
                owner: repo.githubOwner,
                repo: repo.githubRepo,
                number: num,
                method: .squash
            )
            // Detach so the merge response isn't held up by the refresh.
            Task { await refresh(repoId) }
            return .object([
                "merged": .bool(result.value.merged),
                "sha": .string(result.value.sha),
                "account_id": .string(result.successfulAccountId.uuidString),
            ])
        } catch let apiErr as GitHubAPIError {
            throw JSONRPCError(
                code: -32010,
                message: "Merge failed: \(apiErr.message)",
                data: nil
            )
        } catch {
            throw JSONRPCError(
                code: -32010,
                message: "Merge failed: \(error)",
                data: nil
            )
        }
    }
}
