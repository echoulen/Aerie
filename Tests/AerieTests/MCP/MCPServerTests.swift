import XCTest
@testable import Aerie

final class MCPServerTests: XCTestCase {
    func test_dispatch_returnsResultFromRegisteredHandler() async {
        let router = JSONRPCRouter()
        await router.register("tools/list") { _ in
            .object(["tools": .array([.string("aerie_list_repos")])])
        }
        let req = JSONRPCRequest(id: .int(1), method: "tools/list", params: nil)
        let resp = await router.dispatch(req)
        XCTAssertNil(resp.error)
        XCTAssertEqual(resp.result, .object(["tools": .array([.string("aerie_list_repos")])]))
        XCTAssertEqual(resp.id, .int(1))
    }

    func test_dispatch_unknownMethod_returnsMinus32601() async {
        let router = JSONRPCRouter()
        let req = JSONRPCRequest(id: .int(7), method: "no/such", params: nil)
        let resp = await router.dispatch(req)
        XCTAssertEqual(resp.error?.code, -32601)
        XCTAssertNil(resp.result)
        XCTAssertEqual(resp.id, .int(7))
    }

    func test_dispatch_handlerThrowsJSONRPCError_propagates() async {
        let router = JSONRPCRouter()
        await router.register("oops") { _ in
            throw JSONRPCError(code: -32000, message: "custom failure")
        }
        let req = JSONRPCRequest(id: .string("a"), method: "oops", params: nil)
        let resp = await router.dispatch(req)
        XCTAssertEqual(resp.error?.code, -32000)
        XCTAssertEqual(resp.error?.message, "custom failure")
    }

    func test_serverStart_assignsPortAndEndpoint() async throws {
        let router = JSONRPCRouter()
        await router.register("ping") { _ in .string("pong") }
        let server = MCPServer(router: router)
        try await server.start()
        defer { Task { await server.stop() } }

        let endpoint = await server.endpoint
        XCTAssertNotNil(endpoint)
        XCTAssertEqual(endpoint?.scheme, "http")
        XCTAssertEqual(endpoint?.host, "127.0.0.1")
        XCTAssertEqual(endpoint?.path, "/mcp")
        XCTAssertNotNil(endpoint?.port)
        let token = await server.token
        XCTAssertNotNil(token)
        XCTAssertFalse(token!.isEmpty)
    }

    func test_serverRoundtrip_returns200AndJSONRPCResponse() async throws {
        let router = JSONRPCRouter()
        await router.register("tools/list") { _ in
            .object(["tools": .array([.string("aerie_list_repos")])])
        }
        let server = MCPServer(router: router)
        try await server.start()
        defer { Task { await server.stop() } }

        guard let endpoint = await server.endpoint else {
            XCTFail("endpoint missing"); return
        }
        guard let token = await server.token else {
            XCTFail("token missing"); return
        }

        let body = try JSONEncoder().encode(JSONRPCRequest(
            id: .int(1), method: "tools/list", params: nil
        ))
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        let status = http.statusCode
        XCTAssertEqual(status, 200)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertNotNil(decoded.result)
        XCTAssertNil(decoded.error)
        XCTAssertEqual(decoded.id, .int(1))
    }

    func test_rotateToken_invalidatesOldToken() async throws {
        let router = JSONRPCRouter()
        await router.register("tools/list") { _ in .object(["tools": .array([])]) }
        let server = MCPServer(router: router)
        try await server.start()
        defer { Task { await server.stop() } }

        let originalToken = await server.token
        XCTAssertNotNil(originalToken)
        let newToken = await server.rotateToken()
        XCTAssertNotEqual(originalToken, newToken)
        let liveToken = await server.token
        XCTAssertEqual(liveToken, newToken)

        guard let endpoint = await server.endpoint, let oldToken = originalToken else {
            XCTFail("endpoint/token missing"); return
        }

        // Hit the endpoint with the OLD token — must come back as -32001.
        let body = try JSONEncoder().encode(JSONRPCRequest(
            id: .int(1), method: "tools/list", params: nil
        ))
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(oldToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        let status = http.statusCode
        XCTAssertEqual(status, 401)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(decoded.error?.code, -32001)

        // Sanity: the NEW token works.
        var req2 = URLRequest(url: endpoint)
        req2.httpMethod = "POST"
        req2.httpBody = body
        req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req2.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
        let (data2, response2) = try await URLSession.shared.data(for: req2)
        let http2 = response2 as! HTTPURLResponse
        XCTAssertEqual(http2.statusCode, 200)
        let decoded2 = try JSONDecoder().decode(JSONRPCResponse.self, from: data2)
        XCTAssertNil(decoded2.error)
    }

    func test_serverRoundtrip_malformedBody_returns400AndParseError() async throws {
        let router = JSONRPCRouter()
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
        req.httpBody = Data("not json".utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        let status = http.statusCode
        XCTAssertEqual(status, 400)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(decoded.error?.code, -32700)
    }
}
