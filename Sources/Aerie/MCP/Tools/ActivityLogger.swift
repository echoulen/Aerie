import Foundation

/// Persists one row per `tools/call` MCP request to the `mcp_activity`
/// audit table. Best-effort — failures are swallowed so an audit-log
/// outage never breaks the actual MCP response path.
actor ActivityLogger {
    let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// Insert an activity row. Returns when the write completes (or fails
    /// silently). Callers do not need to await this for correctness — but
    /// they typically do, so test assertions can read the row back.
    func record(
        agentId: String?,
        tool: String,
        target: String?,
        isWrite: Bool,
        ok: Bool,
        errorMessage: String?,
        requestJSON: String,
        responseJSON: String
    ) async {
        let record = MCPActivityRecord(
            id: nil,
            at: Date(),
            agentId: agentId,
            tool: tool,
            target: target,
            isWrite: isWrite,
            ok: ok,
            errorMessage: errorMessage,
            requestJSON: requestJSON,
            responseJSON: responseJSON
        )
        try? await db.mcpActivity.insert(record)
    }
}

extension JSONRPCRouter {
    /// Dispatch a JSON-RPC request and, when it's a `tools/call`, write an
    /// activity-log row before returning the response. Non-tools/call
    /// methods are dispatched normally with no logging side-effect.
    ///
    /// The router itself is an actor; this extension is `nonisolated` so
    /// callers can invoke it from any context (server hot path, tests, …).
    /// `dispatch(_:)` is still the appropriate entry point when no
    /// logger is configured — we don't want every test to need a logger.
    nonisolated func dispatchWithLogging(
        _ request: JSONRPCRequest,
        rawRequestJSON: String,
        agentId: String?,
        registry: MCPToolRegistry,
        logger: ActivityLogger?
    ) async -> JSONRPCResponse {
        // Fast path: not a tools/call → no logging side-effects.
        guard request.method == "tools/call" else {
            return await dispatch(request)
        }

        // Extract tool name + best-effort target (repo_id) from params for
        // logging purposes. Validation lives inside the tool itself —
        // we don't pre-reject here.
        var toolName: String? = nil
        var target: String? = nil
        if case .object(let obj) = request.params {
            if case .string(let n) = obj["name"] ?? .null { toolName = n }
            if case .object(let args) = obj["arguments"] ?? .null,
               case .string(let rid) = args["repo_id"] ?? .null {
                target = "repo:\(rid)"
            }
        }
        let isWrite: Bool
        if let toolName, let tool = await registry.tool(named: toolName) {
            isWrite = tool.isWrite
        } else {
            isWrite = false
        }

        let response = await dispatch(request)

        // Best-effort encode for the audit row. We don't fail the call if
        // encoding the response somehow fails.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let responseData = (try? encoder.encode(response)) ?? Data()
        let responseJSON = String(data: responseData, encoding: .utf8) ?? "{}"

        await logger?.record(
            agentId: agentId,
            tool: toolName ?? request.method,
            target: target,
            isWrite: isWrite,
            ok: response.error == nil,
            errorMessage: response.error?.message,
            requestJSON: rawRequestJSON,
            responseJSON: responseJSON
        )
        return response
    }
}
