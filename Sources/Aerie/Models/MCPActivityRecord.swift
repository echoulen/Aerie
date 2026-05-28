import Foundation

/// One entry in the MCP activity audit log. Persisted in `mcp_activity`
/// and trimmed to the most recent 1000 rows.
struct MCPActivityRecord: Codable, Equatable, Identifiable {
    /// SQLite rowid; `nil` before insert, populated after the DAO writes it.
    var id: Int64?
    let at: Date
    let agentId: String?
    let tool: String
    let target: String?
    let isWrite: Bool
    let ok: Bool
    let errorMessage: String?
    let requestJSON: String
    let responseJSON: String
}
