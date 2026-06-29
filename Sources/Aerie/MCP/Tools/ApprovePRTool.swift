import Foundation

/// `aerie_approve_pr` — write tool. Submits an approving review as an eligible
/// account (never the PR author — GitHub forbids self-approval), chosen via
/// `ApproverResolver`. Returns -32010 when no connected account may approve.
struct ApprovePRTool: MCPTool {
    let name = "aerie_approve_pr"
    let description = "Approve a PR as an eligible connected account (not the author)."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repo."),
            "number": JSONSchemaProperty(type: "integer", description: "PR number."),
            "body": JSONSchemaProperty(type: "string", description: "Optional review comment body."),
        ],
        required: ["repo_id", "number"]
    )

    let db: AppDatabase
    let api: MultiAccountAPI
    let accounts: @Sendable () async -> [GitHubAccount]
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        let num = try intParam(params, key: "number")
        let body = optionalStringParam(params, key: "body")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        let prs = try await db.prCache.prs(forRepo: repoId)
        guard let pr = prs.first(where: { $0.number == num }) else {
            throw JSONRPCError(code: -32602, message: "Unknown PR \(num) for this repo", data: nil)
        }
        let lastApprover = LastApproverStore(settings: db.settings)
        let resolution = ApproverResolver.resolve(
            accounts: await accounts(),
            boundAccountId: repo.primaryAccountId,
            authorLogin: pr.authorLogin,
            preferredLogin: await lastApprover.login(forRepo: repoId)
        )
        guard let approver = resolution.defaultApprover else {
            throw JSONRPCError(
                code: -32010,
                message: "No eligible account can approve this PR (only the author is connected).",
                data: nil
            )
        }
        do {
            let result = try await api.approvePR(
                owner: repo.githubOwner, repo: repo.githubRepo,
                number: num, body: body, accountId: approver.id
            )
            await lastApprover.record(approver.login, forRepo: repoId)
            Task { await refresh(repoId) }
            return .object([
                "approved": .bool(true),
                "account_id": .string(result.successfulAccountId.uuidString),
                "approver_login": .string(approver.login),
            ])
        } catch let apiErr as GitHubAPIError {
            throw JSONRPCError(code: -32010, message: "Approve failed: \(apiErr.message)", data: nil)
        } catch {
            throw JSONRPCError(code: -32010, message: "Approve failed: \(error)", data: nil)
        }
    }
}
