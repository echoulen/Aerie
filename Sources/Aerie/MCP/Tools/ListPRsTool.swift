import Foundation

/// `aerie_list_prs` — read-only list of cached PRs.
///
/// When `repo_id` is provided, returns PRs for that repository only.
/// When omitted (or unparseable), returns every cached PR across every
/// tracked repository.
struct ListPRsTool: MCPTool {
    let name = "aerie_list_prs"
    let description = "List cached PRs across all repos, or for a single repo when repo_id is provided."
    let isWrite = false
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(
                type: "string",
                description: "Optional. UUID of the repository to filter by."
            ),
        ],
        required: []
    )

    let db: AppDatabase

    func handle(params: JSONValue?) async throws -> JSONValue {
        // repo_id is optional — silently ignore malformed values rather than
        // throwing, mirroring the "filter is best-effort" semantics.
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
            // Match the requested repo if present; otherwise fall through to
            // an empty list rather than implicitly returning every repo's PRs.
            if try await db.repos.find(id: id) != nil {
                repoIds = [id]
            } else {
                repoIds = []
            }
        } else {
            let all = try await db.repos.all()
            repoIds = all.map(\.id)
        }

        var prs: [PullRequest] = []
        for id in repoIds {
            prs.append(contentsOf: try await db.prCache.prs(forRepo: id))
        }
        let encoded = try encodeAsJSONValue(prs)
        return .object(["prs": encoded])
    }
}
