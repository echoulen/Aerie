import Foundation

/// `aerie_force_checkout` — write tool. Force-checks-out the repo onto a PR's
/// origin branch (`git checkout -f -B <branch> origin/<branch>`), discarding a
/// dirty tree and divergent local commits. Fetch authenticates as the repo's
/// bound account.
struct ForceCheckoutTool: MCPTool {
    let name = "aerie_force_checkout"
    let description = "Force-checkout the repo onto a PR's origin branch (discards local changes)."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repo."),
            "branch": JSONSchemaProperty(type: "string", description: "Branch to check out (the PR's source branch)."),
        ],
        required: ["repo_id", "branch"]
    )

    let db: AppDatabase
    let git: any GitService
    let accountToken: @Sendable (UUID) async -> String?
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        let branch = try stringParam(params, key: "branch")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        do {
            let token = await accountToken(repo.primaryAccountId)
            try await git.forceCheckout(repoAt: repo.localPath, branch: branch, token: token)
            Task { await refresh(repoId) }
            return .object(["checked_out": .string(branch)])
        } catch {
            throw JSONRPCError(code: -32011, message: "Force checkout failed: \(error)", data: nil)
        }
    }
}
