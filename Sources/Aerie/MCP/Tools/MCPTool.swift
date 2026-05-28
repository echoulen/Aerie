import Foundation

/// Minimal JSON Schema description for a tool's input. We don't enforce
/// validation — the schema is published to clients via `tools/list`.
struct JSONSchema: Codable, Equatable {
    let type: String                                // "object"
    let properties: [String: JSONSchemaProperty]
    let required: [String]
}

struct JSONSchemaProperty: Codable, Equatable {
    let type: String
    let description: String?
}

/// A single MCP tool exposed via `tools/list` / `tools/call`.
///
/// Implementations live alongside this protocol under `MCP/Tools/`. Each
/// concrete tool carries its own dependencies (DAO, services, refresh
/// closures) so the registry stays a thin lookup table.
protocol MCPTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: JSONSchema { get }
    /// `true` for tools that mutate external state (merge, hard reset).
    /// Surfaced via the activity log so the UI can distinguish reads/writes.
    var isWrite: Bool { get }

    /// Returns a JSONValue result. Throws `JSONRPCError` on validation /
    /// semantic failures so the router can map them to the on-the-wire
    /// error envelope.
    func handle(params: JSONValue?) async throws -> JSONValue
}
