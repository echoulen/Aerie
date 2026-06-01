import Foundation

/// `aerie_get_local_status` — return the cached `LocalGitStatus` for a
/// repository. Returns JSON-null when the cache has no row for the id
/// (e.g. the repo exists but no git scan has populated it yet).
struct GetLocalStatusTool: MCPTool {
    let name = "aerie_get_local_status"
    let description = "Read the cached local git status for a repository."
    let isWrite = false
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(
                type: "string",
                description: "UUID of the repository."
            ),
        ],
        required: ["repo_id"]
    )

    let db: AppDatabase

    func handle(params: JSONValue?) async throws -> JSONValue {
        let id = try uuidParam(params, key: "repo_id")
        guard let status = try await db.gitStatusCache.status(forRepo: id) else {
            return .null
        }
        return try encodeAsJSONValue(status)
    }
}
