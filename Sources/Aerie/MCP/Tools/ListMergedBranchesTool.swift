import Foundation

/// `aerie_list_merged_branches` — read-only list of detected already-merged
/// off-default branches (the `merged · #N` pill data, #64). 0-or-1 per repo;
/// collects the non-nil rows across all repos (or one when filtered).
struct ListMergedBranchesTool: MCPTool {
    let name = "aerie_list_merged_branches"
    let description = "List repos' detected already-merged off-default branches (the 'merged · #N' state)."
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

        var infos: [MergedBranchInfo] = []
        for id in repoIds {
            if let info = try await db.mergedBranchCache.info(forRepo: id) {
                infos.append(info)
            }
        }
        let encoded = try encodeAsJSONValue(infos)
        return .object(["merged_branches": encoded])
    }
}
