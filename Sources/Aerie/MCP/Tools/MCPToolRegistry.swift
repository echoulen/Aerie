import Foundation

/// Lookup table for `MCPTool` instances. Tools are registered at startup
/// and never removed. The registry knows how to render itself as a
/// `tools/list` response and how to dispatch a `tools/call` request.
actor MCPToolRegistry {
    private var tools: [String: any MCPTool] = [:]

    init() {}

    func register(_ tool: any MCPTool) {
        tools[tool.name] = tool
    }

    func tool(named: String) -> (any MCPTool)? { tools[named] }

    /// Powers the `tools/list` MCP method. Tools are sorted by name so the
    /// output is deterministic across runs (also useful for snapshots).
    func list() -> JSONValue {
        let items: [JSONValue] = tools.values
            .sorted { $0.name < $1.name }
            .map { t in
                .object([
                    "name": .string(t.name),
                    "description": .string(t.description),
                    "inputSchema": (try? encodeAsJSONValue(t.inputSchema)) ?? .object([:]),
                ])
            }
        return .object(["tools": .array(items)])
    }

    /// Dispatch a `tools/call` JSON-RPC request.
    /// Expected params shape: `{ "name": "tool_name", "arguments": { ... } }`.
    func dispatch(params: JSONValue?) async throws -> JSONValue {
        guard case .object(let obj) = params,
              case .string(let name) = obj["name"] ?? .null else {
            throw JSONRPCError(
                code: -32602,
                message: "tools/call requires { name, arguments }",
                data: nil
            )
        }
        guard let tool = tools[name] else {
            throw JSONRPCError(code: -32601, message: "Unknown tool: \(name)", data: nil)
        }
        let args = obj["arguments"]
        return try await tool.handle(params: args)
    }
}

/// Encode any `Encodable` value into a `JSONValue` via a JSON round-trip.
/// Used to project `JSONSchema` (Codable) into the untyped envelope we
/// expose on the wire.
func encodeAsJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}
