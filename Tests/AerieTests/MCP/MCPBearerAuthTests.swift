import XCTest
import Hummingbird
import HTTPTypes
import NIOCore
@testable import Aerie

final class MCPBearerAuthTests: XCTestCase {
    // MARK: - Integration against the live server

    func test_returnsMinus32001_whenNoAuthHeader() async throws {
        let router = JSONRPCRouter()
        await router.register("ping") { _ in .string("pong") }
        let server = MCPServer(router: router)
        try await server.start()
        defer { Task { await server.stop() } }

        guard let endpoint = await server.endpoint else {
            XCTFail("endpoint missing"); return
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(
            JSONRPCRequest(id: .int(1), method: "ping", params: nil)
        )
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Deliberately no Authorization header.

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        let status = http.statusCode
        XCTAssertEqual(status, 401)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(decoded.error?.code, -32001)
    }

    func test_returnsMinus32001_whenWrongToken() async throws {
        let router = JSONRPCRouter()
        await router.register("ping") { _ in .string("pong") }
        let server = MCPServer(router: router)
        try await server.start()
        defer { Task { await server.stop() } }

        guard let endpoint = await server.endpoint else {
            XCTFail("endpoint missing"); return
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(
            JSONRPCRequest(id: .int(1), method: "ping", params: nil)
        )
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer not-the-right-one", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        let status = http.statusCode
        XCTAssertEqual(status, 401)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(decoded.error?.code, -32001)
    }

    func test_returnsResult_whenRightToken() async throws {
        let router = JSONRPCRouter()
        await router.register("ping") { _ in .string("pong") }
        let server = MCPServer(router: router)
        try await server.start()
        defer { Task { await server.stop() } }

        guard let endpoint = await server.endpoint else {
            XCTFail("endpoint missing"); return
        }
        guard let token = await server.token else {
            XCTFail("token missing"); return
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(
            JSONRPCRequest(id: .int(42), method: "ping", params: nil)
        )
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        let status = http.statusCode
        XCTAssertEqual(status, 200)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(decoded.result, .string("pong"))
        XCTAssertEqual(decoded.id, .int(42))
    }

    // MARK: - Unit-level cover of the no-token-configured branch

    func test_authenticate_returnsDeny_whenServerHasNoToken() async {
        // This branch is impossible to hit through MCPServer (start() always
        // generates a token), so we test MCPBearerAuth directly via the
        // tokenProvider returning nil.
        let auth = MCPBearerAuth(tokenProvider: { nil })
        // We need a real Hummingbird Request to call authenticate(_:). The
        // simplest way is to construct one by hand — we don't care about the
        // headers since the nil-token branch short-circuits first.
        // Construct via HTTPRequest:
        let head = HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: "/mcp")
        let request = Request(head: head, body: .init(buffer: .init()))

        let decision = await auth.authenticate(request)
        switch decision {
        case .allow:
            XCTFail("Expected deny when no token configured")
        case .deny(let envelope):
            XCTAssertEqual(envelope.error?.code, -32001)
            XCTAssertEqual(envelope.error?.message, "No server token configured")
        }
    }
}
