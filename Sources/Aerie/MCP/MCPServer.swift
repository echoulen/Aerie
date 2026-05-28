import Foundation
import Hummingbird
import HTTPTypes
import Logging
import NIOCore

/// HTTP host the MCP server binds to. Always loopback — the discovery file
/// (Phase 18.3) plus bearer auth (Phase 18.2) are the only ways in.
private let mcpHost = "127.0.0.1"

/// Owns the Hummingbird application + its background task.
///
/// We bind to `127.0.0.1:0` and capture the assigned port via Hummingbird's
/// ``Application.init(...onServerRunning:)`` callback — which is invoked with
/// the bound channel, whose `localAddress.port` gives us the OS-assigned
/// ephemeral port.
///
/// Lifecycle:
/// - ``start()`` blocks until the listening channel is up *and* the port has
///   been captured. After it returns, ``endpoint`` and ``token`` are valid.
/// - ``stop()`` cancels the background task and waits for it to finish.
actor MCPServer {
    let router: JSONRPCRouter
    /// Tool registry, used by `dispatchWithLogging` to look up isWrite +
    /// surface the tool name in the audit log. Optional so tests that
    /// just exercise the router don't need to wire one up.
    let registry: MCPToolRegistry?
    /// Activity logger. When `nil`, the server skips audit logging — the
    /// router uses the plain `dispatch(_:)` path.
    let logger: ActivityLogger?

    /// Bearer token for clients. Generated per `start()` from `UUID().uuidString`.
    /// Nil before first start.
    private(set) var token: String?

    /// Assigned port, captured in `onServerRunning`. Nil before start completes.
    private var port: Int?

    /// Background task running `Application.runService()`. Cancelled by `stop()`.
    private var serverTask: Task<Void, Error>?

    init(
        router: JSONRPCRouter,
        registry: MCPToolRegistry? = nil,
        logger: ActivityLogger? = nil
    ) {
        self.router = router
        self.registry = registry
        self.logger = logger
    }

    /// Full MCP endpoint URL, e.g. `http://127.0.0.1:54321/mcp`.
    /// Nil before the server has started.
    var endpoint: URL? {
        guard let port else { return nil }
        return URL(string: "http://\(mcpHost):\(port)/mcp")
    }

    /// Start listening. Resolves once the port has been bound.
    func start() async throws {
        guard serverTask == nil else { return }

        let generatedToken = UUID().uuidString
        self.token = generatedToken

        // Snapshot captures for the responder closure (it's @Sendable and
        // must not capture `self`). Router/registry/logger are value-ish or
        // actor references — fine to copy. The bearer token, however, must
        // be queried *live* so `rotateToken()` actually invalidates the old
        // value. We capture a weak handle to self for that.
        let routerActor = self.router
        let registryActor = self.registry
        let activityLogger = self.logger
        let auth = MCPBearerAuth(tokenProvider: { [weak self] in
            await self?.token
        })

        let hbRouter = Router()
        hbRouter.post("/mcp") { request, _ -> Response in
            await Self.handleMCPRequest(
                request: request,
                router: routerActor,
                auth: auth,
                registry: registryActor,
                logger: activityLogger
            )
        }

        // Capture the bound port via onServerRunning. The channel's
        // localAddress is the only reliable way to learn the OS-assigned
        // port when binding to port 0.
        let portStream = AsyncStream<Int>.makeStream()
        let onRunning: @Sendable (any Channel) async -> Void = { channel in
            if let p = channel.localAddress?.port {
                portStream.continuation.yield(p)
                portStream.continuation.finish()
            } else {
                portStream.continuation.finish()
            }
        }

        // Quiet the default Hummingbird logger so tests don't spam stdout.
        // Hummingbird emits a couple of "Server shutdown error: Already closed"
        // log lines at .error level when stop() races with the listening channel
        // being torn down — they're harmless, so we pin the level to .critical.
        var logger = Logger(label: "Aerie.MCPServer")
        logger.logLevel = .critical

        let config = ApplicationConfiguration(
            address: .hostname(mcpHost, port: 0),
            serverName: "Aerie-MCP"
        )

        let app = Application(
            router: hbRouter,
            configuration: config,
            onServerRunning: onRunning,
            logger: logger
        )

        // Kick off the server in the background. We don't `await` it — we
        // wait on the port stream instead.
        let task = Task {
            try await app.runService()
        }
        self.serverTask = task

        // Block until either the port arrives or the server task fails first.
        // If runService() throws synchronously (e.g. port already in use,
        // though unlikely with port 0), we propagate that.
        let observedPort: Int? = await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                var iter = portStream.stream.makeAsyncIterator()
                return await iter.next()
            }
            // Don't wait forever — if the server died early the port stream
            // will never yield and the test would hang. Bound at 5s.
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }

        guard let observedPort else {
            // Server failed to bind. Surface the task's error if any.
            task.cancel()
            self.serverTask = nil
            self.token = nil
            // Best-effort: pull the actual error out of the task.
            do {
                _ = try await task.value
                throw MCPServerError.startupTimeout
            } catch {
                throw error
            }
        }
        self.port = observedPort
    }

    /// Generate a fresh bearer token and replace the current one. Returns the
    /// new token. Subsequent requests must carry the new value or the bearer
    /// middleware will respond with -32001.
    ///
    /// Callers (the integration layer in `AerieApp`) are responsible for
    /// re-writing the discovery file and `~/.claude/.mcp.json` with the new
    /// token; this function only mutates server state.
    func rotateToken() -> String {
        let newToken = UUID().uuidString
        self.token = newToken
        return newToken
    }

    /// Stop the server. Idempotent — calling on a stopped server is a no-op.
    func stop() async {
        guard let task = serverTask else { return }
        task.cancel()
        // Hummingbird's runService observes cancellation through the
        // ServiceGroup graceful-shutdown path and returns normally. Errors
        // here (including CancellationError) are not interesting.
        _ = try? await task.value
        self.serverTask = nil
        self.port = nil
        self.token = nil
    }

    // MARK: - Request handling

    private static func handleMCPRequest(
        request: Request,
        router: JSONRPCRouter,
        auth: MCPBearerAuth,
        registry: MCPToolRegistry?,
        logger: ActivityLogger?
    ) async -> Response {
        // Bearer check up front. We fail closed with HTTP 401 + a JSON-RPC
        // envelope carrying -32001 so clients see a consistent shape.
        switch await auth.authenticate(request) {
        case .allow:
            break
        case .deny(let envelope):
            return Self.jsonResponse(status: .unauthorized, body: envelope)
        }

        // Read the body (cap at 1 MiB — JSON-RPC payloads should be tiny).
        let bytes: ByteBuffer
        do {
            bytes = try await request.body.collect(upTo: 1 << 20)
        } catch {
            return Self.jsonResponse(
                status: .badRequest,
                body: .failure(id: nil, code: -32700, message: "Parse error: body read failed")
            )
        }

        let data = Data(buffer: bytes)
        let decoder = JSONDecoder()
        let rpcRequest: JSONRPCRequest
        do {
            rpcRequest = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            return Self.jsonResponse(
                status: .badRequest,
                body: .failure(id: nil, code: -32700, message: "Parse error")
            )
        }

        // Dispatch path:
        // - With registry + logger configured → use the logging path so
        //   tools/call traffic lands in mcp_activity. The agent id comes
        //   from the X-MCP-Agent-Id header; spec says "unknown" when missing.
        // - Without either → plain dispatch.
        let response: JSONRPCResponse
        if let registry, let logger {
            let agentField = HTTPField.Name("X-MCP-Agent-Id")!
            let agentId = request.headers[agentField] ?? "unknown"
            let rawJSON = String(data: data, encoding: .utf8) ?? ""
            response = await router.dispatchWithLogging(
                rpcRequest,
                rawRequestJSON: rawJSON,
                agentId: agentId,
                registry: registry,
                logger: logger
            )
        } else {
            response = await router.dispatch(rpcRequest)
        }
        return Self.jsonResponse(status: .ok, body: response)
    }

    /// Build an `application/json` response from an encodable envelope.
    /// Failures here would be programmer error (we control the input).
    static func jsonResponse(status: HTTPResponse.Status, body: JSONRPCResponse) -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(body)
        } catch {
            // Last-ditch fallback if JSON encoding ever fails for some reason.
            data = Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal encoding error\"}}".utf8)
        }
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(data: data))
        )
    }
}

enum MCPServerError: Error, Equatable {
    /// `start()` waited for the listening channel to come up and gave up.
    case startupTimeout
    /// Auth not yet configured — returned by the bearer middleware via JSON-RPC.
    /// Not thrown directly; included here for documentation parity.
    case unauthorized
}
