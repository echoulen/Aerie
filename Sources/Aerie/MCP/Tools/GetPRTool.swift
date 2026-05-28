import Foundation

/// `aerie_get_pr` — single-PR lookup by `(repo_id, number)`. Returns
/// JSON-null when no cached row exists for that combination.
struct GetPRTool: MCPTool {
    let name = "aerie_get_pr"
    let description = "Get a single PR by repo_id + number."
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

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        let num = try intParam(params, key: "number")
        let prs = try await db.prCache.prs(forRepo: repoId)
        guard let match = prs.first(where: { $0.number == num }) else {
            return .null
        }
        return try encodeAsJSONValue(match)
    }
}
