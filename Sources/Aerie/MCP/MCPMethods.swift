import Foundation

/// Registers the standard MCP JSON-RPC methods on a ``JSONRPCRouter``,
/// delegating tool traffic to a ``MCPToolRegistry``.
///
/// Without this, the router's handler table is empty and *every* request —
/// including the `initialize` handshake — fails with `-32601 Method not found`,
/// so a client like Claude Code can never connect (it reports
/// "Failed to reconnect … -32601"). Installing these handlers is what turns the
/// already-running HTTP server (`MCPServer`) into a working MCP endpoint.
enum MCPMethods {
    struct ServerInfo: Sendable, Equatable {
        let name: String
        let version: String
    }

    /// Echoed back to clients that don't send their own `protocolVersion`.
    /// MCP clients accept the server echoing the version they requested.
    static let defaultProtocolVersion = "2024-11-05"

    /// Register `initialize`, `notifications/initialized`, `ping`,
    /// `tools/list`, and `tools/call`. Idempotent at the router level
    /// (re-registering a method just replaces its handler).
    static func install(
        on router: JSONRPCRouter,
        registry: MCPToolRegistry,
        serverInfo: ServerInfo
    ) async {
        let fallbackVersion = defaultProtocolVersion

        await router.register("initialize") { params in
            // Echo the client's requested protocol version when present, so we
            // negotiate to whatever it speaks; fall back otherwise.
            var version = fallbackVersion
            if case let .object(obj)? = params,
               case let .string(requested)? = obj["protocolVersion"] {
                version = requested
            }
            return .object([
                "protocolVersion": .string(version),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string(serverInfo.name),
                    "version": .string(serverInfo.version),
                ]),
            ])
        }

        // Post-handshake notification from the client. No result payload is
        // expected; returning null keeps the envelope well-formed.
        await router.register("notifications/initialized") { _ in .null }

        // MCP `ping` → empty result object.
        await router.register("ping") { _ in .object([:]) }

        await router.register("tools/list") { _ in await registry.list() }

        await router.register("tools/call") { params in
            let raw = try await registry.dispatch(params: params)
            // MCP clients read tool output from `result.content` (a
            // `CallToolResult`), NOT the bare object. Returning the raw value
            // makes the call "succeed" while the client finds no content and
            // renders it as empty. Wrap it: a text content item carrying the
            // JSON for universal compatibility, plus `structuredContent` (the
            // raw object) for clients that consume it.
            return .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(Self.jsonText(raw)),
                    ])
                ]),
                "structuredContent": raw,
                "isError": .bool(false),
            ])
        }
    }

    /// Serialize a `JSONValue` to a compact JSON string (deterministic key
    /// order) for embedding as MCP text content.
    private static func jsonText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }
}
