import Foundation

/// `aerie_get_pr_diff` — read-only, live fetch of a PR's changed files and
/// per-file unified-diff patches. Not cached; uses the repo's bound account
/// (one precise call). `PRFileChange` isn't Codable, so the JSON is hand-built.
struct GetPRDiffTool: MCPTool {
    let name = "aerie_get_pr_diff"
    let description = "Get a PR's changed files with per-file unified-diff patches."
    let isWrite = false
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

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        let num = try intParam(params, key: "number")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        do {
            let result = try await api.fetchPRFiles(
                owner: repo.githubOwner, repo: repo.githubRepo,
                number: num, accountId: repo.primaryAccountId
            )
            let items: [JSONValue] = result.value.map { f in
                .object([
                    "filename": .string(f.filename),
                    "status": .string(f.status.label),
                    "additions": .int(f.additions),
                    "deletions": .int(f.deletions),
                    "patch": f.patch.map(JSONValue.string) ?? .null,
                ])
            }
            return .object(["files": .array(items)])
        } catch let apiErr as GitHubAPIError {
            throw JSONRPCError(code: -32010, message: "Fetch diff failed: \(apiErr.message)", data: nil)
        } catch {
            throw JSONRPCError(code: -32010, message: "Fetch diff failed: \(error)", data: nil)
        }
    }
}
