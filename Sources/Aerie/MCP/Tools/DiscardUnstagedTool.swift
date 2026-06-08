import Foundation

/// `aerie_discard_unstaged` — write tool. Discards unstaged changes:
/// `git restore .` + `git clean -fd` (keeps staged/committed/.gitignore'd).
struct DiscardUnstagedTool: MCPTool {
    let name = "aerie_discard_unstaged"
    let description = "Discard all unstaged changes in a repo (restore tracked + remove untracked)."
    let isWrite = true
    let inputSchema = JSONSchema(
        type: "object",
        properties: [
            "repo_id": JSONSchemaProperty(type: "string", description: "UUID of the repo."),
        ],
        required: ["repo_id"]
    )

    let db: AppDatabase
    let git: any GitService
    let refresh: @Sendable (UUID) async -> Void

    func handle(params: JSONValue?) async throws -> JSONValue {
        let repoId = try uuidParam(params, key: "repo_id")
        guard let repo = try await db.repos.find(id: repoId) else {
            throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
        }
        do {
            try await git.discardUnstaged(repoAt: repo.localPath)
            Task { await refresh(repoId) }
            return .object(["discarded": .bool(true)])
        } catch {
            throw JSONRPCError(code: -32011, message: "Discard failed: \(error)", data: nil)
        }
    }
}
