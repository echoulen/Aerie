import Foundation

/// `aerie_get_pr_local_state` — return the cached `PRLocalState` (source
/// branch existence, dirty/ahead/behind counters) for a PR. Returns
/// JSON-null when the cache has no row for the id.
struct GetPRLocalStateTool: MCPTool {
    let name = "aerie_get_pr_local_state"
    let description = "Get the cached local state of a PR's source branch."
    let isWrite = false
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "pr_id": JSONSchemaProperty(
                type: "string",
                description: "UUID of the PR."
            ),
        ],
        required: ["pr_id"]
    )

    let db: AppDatabase

    func handle(params: JSONValue?) async throws -> JSONValue {
        let prId = try uuidParam(params, key: "pr_id")
        guard let state = try await db.prLocalStateCache.state(forPr: prId) else {
            return .null
        }
        return try encodeAsJSONValue(state)
    }
}
