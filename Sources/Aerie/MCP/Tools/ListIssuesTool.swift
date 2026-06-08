import Foundation

/// `aerie_list_issues` — read-only list of cached open issues. Mirrors
/// `ListPRsTool`: all tracked repos when `repo_id` is omitted, one repo when
/// given (unknown id → empty list).
struct ListIssuesTool: MCPTool {
    let name = "aerie_list_issues"
    let description = "List cached open issues across all repos, or for a single repo when repo_id is provided."
    let isWrite = false
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "Optional. UUID of the repository to filter by."),
        ],
        required: []
    )

    let db: AppDatabase

    func handle(params: JSONValue?) async throws -> JSONValue {
        let filterId: UUID?
        if case .object(let obj) = params,
           case .string(let s) = obj["repo_id"] ?? .null,
           let id = UUID(uuidString: s) {
            filterId = id
        } else {
            filterId = nil
        }

        let repoIds: [UUID]
        if let id = filterId {
            repoIds = (try await db.repos.find(id: id) != nil) ? [id] : []
        } else {
            repoIds = try await db.repos.all().map(\.id)
        }

        var issues: [Issue] = []
        for id in repoIds {
            issues.append(contentsOf: try await db.issueCache.issues(forRepo: id))
        }
        let encoded = try encodeAsJSONValue(issues)
        return .object(["issues": encoded])
    }
}
