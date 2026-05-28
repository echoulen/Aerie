import XCTest
@testable import Aerie

/// Targeted tests for the bits of Phase 18.4 that *can* be exercised in
/// isolation. Full lifecycle through ``AerieApp`` requires an NSApplication
/// scene to run, which is not feasible from a unit test bundle, so we cover
/// the structural pieces (token / endpoint / stop behaviour) here.
final class MCPServerLifecycleTests: XCTestCase {
    func test_mcpServer_generatesTokenOnStart() async throws {
        let server = MCPServer(router: JSONRPCRouter())
        let preToken = await server.token
        XCTAssertNil(preToken, "token should be nil before start")

        try await server.start()
        defer { Task { await server.stop() } }

        let postToken = await server.token
        XCTAssertNotNil(postToken)
        XCTAssertFalse(postToken!.isEmpty)
        // UUID().uuidString is 36 chars — sanity check the shape.
        XCTAssertEqual(postToken!.count, 36)
    }

    func test_mcpServer_endpoint_includesAssignedPort() async throws {
        let server = MCPServer(router: JSONRPCRouter())
        try await server.start()
        defer { Task { await server.stop() } }

        let endpoint = await server.endpoint
        XCTAssertNotNil(endpoint)
        XCTAssertEqual(endpoint?.host, "127.0.0.1")
        XCTAssertEqual(endpoint?.path, "/mcp")
        let port = endpoint?.port
        XCTAssertNotNil(port)
        // Ephemeral port allocations on macOS land well above 1024.
        XCTAssertGreaterThan(port!, 1024)
    }

    func test_mcpServer_stop_clearsEndpointAndToken() async throws {
        let server = MCPServer(router: JSONRPCRouter())
        try await server.start()

        let beforeEndpoint = await server.endpoint
        XCTAssertNotNil(beforeEndpoint)

        await server.stop()

        let afterEndpoint = await server.endpoint
        let afterToken = await server.token
        XCTAssertNil(afterEndpoint)
        XCTAssertNil(afterToken)
    }

    func test_mcpServer_canRestartAfterStop() async throws {
        // Sanity check that the actor's state is left in a re-startable
        // shape after stop() — important for the AerieApp lifecycle, where
        // an unrelated bug elsewhere shouldn't permanently bork MCP.
        let server = MCPServer(router: JSONRPCRouter())
        try await server.start()
        let firstPort = await server.endpoint?.port
        await server.stop()

        try await server.start()
        defer { Task { await server.stop() } }
        let secondPort = await server.endpoint?.port

        XCTAssertNotNil(firstPort)
        XCTAssertNotNil(secondPort)
    }
}
