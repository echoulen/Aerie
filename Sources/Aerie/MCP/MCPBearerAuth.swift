import Foundation
import Hummingbird
import HTTPTypes

/// Decision returned by ``MCPBearerAuth/authenticate(_:)``.
enum MCPAuthDecision: Equatable {
    /// Header matched — let the request through.
    case allow
    /// Header missing / malformed / wrong — fail closed with the given
    /// JSON-RPC envelope (HTTP 401).
    case deny(JSONRPCResponse)
}

/// Validates the `Authorization: Bearer <token>` header on incoming MCP
/// requests. The token is provided by a closure so the server can rotate
/// it without rebuilding the middleware.
///
/// Failure modes (per Phase 18.2 design):
/// * No token configured server-side -> -32001 "No server token configured".
/// * Missing / mismatched header -> -32001 "Unauthorized".
///
/// We return the JSON-RPC envelope along with the deny decision so the
/// caller writes a real JSON-RPC body even on 401 — clients that speak
/// JSON-RPC can parse the failure uniformly without sniffing the HTTP
/// status code.
struct MCPBearerAuth: Sendable {
    let tokenProvider: @Sendable () async -> String?

    init(tokenProvider: @escaping @Sendable () async -> String?) {
        self.tokenProvider = tokenProvider
    }

    func authenticate(_ request: Request) async -> MCPAuthDecision {
        guard let expected = await tokenProvider() else {
            return .deny(.failure(id: nil, code: -32001, message: "No server token configured"))
        }
        guard let header = request.headers[.authorization] else {
            return .deny(.failure(id: nil, code: -32001, message: "Unauthorized"))
        }
        let expectedHeader = "Bearer \(expected)"
        // Constant-time compare would be slightly better, but we're on
        // loopback only and a timing oracle against a 128-bit UUID is not
        // a practical attack surface. Straight `==` is fine.
        guard header == expectedHeader else {
            return .deny(.failure(id: nil, code: -32001, message: "Unauthorized"))
        }
        return .allow
    }
}
