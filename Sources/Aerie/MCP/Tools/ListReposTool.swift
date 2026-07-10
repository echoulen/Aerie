import Foundation

/// `aerie_list_repos` — read-only enumeration of every tracked repository.
///
/// The returned shape is a JSON object with a single `repos` array so we
/// can attach metadata later (rate-limit snapshot, etc.) without breaking
/// existing clients.
struct ListReposTool: MCPTool {
    let name = "aerie_list_repos"
    let description = "List all tracked repositories with their local + GitHub identifiers."
    let isWrite = false
    let inputSchema = JSONSchema(type: "object", properties: [:], required: [])

    let db: AppDatabase

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repos = try await db.repos.all()
        let items: [JSONValue] = repos.map { r in
            .object([
                "id": .string(r.id.uuidString),
                "name": .string(r.name),
                "local_path": .string(r.localPath.path),
                "owner": .string(r.githubOwner),
                "repo": .string(r.githubRepo),
                "default_branch": .string(r.defaultBranch),
                "hidden": .bool(r.hidden),
                "api_sync_disabled": .bool(r.apiSyncDisabled),
            ])
        }
        return .object(["repos": .array(items)])
    }
}
