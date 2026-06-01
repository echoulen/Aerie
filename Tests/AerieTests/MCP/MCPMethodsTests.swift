import XCTest
@testable import Aerie

final class MCPMethodsTests: XCTestCase {
    /// Minimal tool so `tools/list` / `tools/call` have something to route
    /// without pulling in real app dependencies.
    private struct StubTool: MCPTool {
        let name = "stub_tool"
        let description = "stub"
        let isWrite = false
        let inputSchema = JSONSchema(type: "object", properties: [:], required: [])
        func handle(params: JSONValue?) async throws -> JSONValue { .string("ok") }
    }

    private func makeRouter(withStub: Bool = false) async -> JSONRPCRouter {
        let router = JSONRPCRouter()
        let registry = MCPToolRegistry()
        if withStub { await registry.register(StubTool()) }
        await MCPMethods.install(
            on: router,
            registry: registry,
            serverInfo: .init(name: "Aerie", version: "9.9.9")
        )
        return router
    }

    func test_initialize_echoesProtocolVersion_andAdvertisesTools() async {
        let router = await makeRouter()
        let res = await router.dispatch(JSONRPCRequest(
            id: .int(1), method: "initialize",
            params: .object(["protocolVersion": .string("2025-06-18")])
        ))
        XCTAssertNil(res.error)
        guard case let .object(obj)? = res.result else { return XCTFail("no result") }
        XCTAssertEqual(obj["protocolVersion"], .string("2025-06-18"))
        guard case let .object(caps)? = obj["capabilities"] else { return XCTFail("no caps") }
        XCTAssertNotNil(caps["tools"])
        guard case let .object(info)? = obj["serverInfo"] else { return XCTFail("no serverInfo") }
        XCTAssertEqual(info["name"], .string("Aerie"))
        XCTAssertEqual(info["version"], .string("9.9.9"))
    }

    func test_initialize_fallsBackWhenNoVersionGiven() async {
        let router = await makeRouter()
        let res = await router.dispatch(
            JSONRPCRequest(id: .int(1), method: "initialize", params: nil)
        )
        guard case let .object(obj)? = res.result else { return XCTFail("no result") }
        XCTAssertEqual(obj["protocolVersion"], .string(MCPMethods.defaultProtocolVersion))
    }

    func test_toolsList_returnsRegisteredTools() async {
        let router = await makeRouter(withStub: true)
        let res = await router.dispatch(
            JSONRPCRequest(id: .int(1), method: "tools/list", params: nil)
        )
        guard case let .object(obj)? = res.result,
              case let .array(tools)? = obj["tools"] else { return XCTFail("no tools array") }
        XCTAssertEqual(tools.count, 1)
    }

    func test_toolsCall_routesToTool() async {
        let router = await makeRouter(withStub: true)
        let res = await router.dispatch(JSONRPCRequest(
            id: .int(1), method: "tools/call",
            params: .object(["name": .string("stub_tool"), "arguments": .object([:])])
        ))
        XCTAssertNil(res.error)
        XCTAssertEqual(res.result, .string("ok"))
    }

    func test_toolsCall_unknownTool_returnsMinus32601() async {
        let router = await makeRouter()
        let res = await router.dispatch(JSONRPCRequest(
            id: .int(1), method: "tools/call",
            params: .object(["name": .string("nope"), "arguments": .object([:])])
        ))
        XCTAssertEqual(res.error?.code, -32601)
    }

    func test_ping_returnsEmptyObject() async {
        let router = await makeRouter()
        let res = await router.dispatch(
            JSONRPCRequest(id: .int(1), method: "ping", params: nil)
        )
        XCTAssertEqual(res.result, .object([:]))
    }

    func test_notificationsInitialized_returnsNull() async {
        let router = await makeRouter()
        let res = await router.dispatch(
            JSONRPCRequest(id: nil, method: "notifications/initialized", params: nil)
        )
        XCTAssertEqual(res.result, .null)
    }

    func test_unknownMethod_stillReturnsMinus32601() async {
        let router = await makeRouter()
        let res = await router.dispatch(
            JSONRPCRequest(id: .int(1), method: "no/such/method", params: nil)
        )
        XCTAssertEqual(res.error?.code, -32601)
    }
}
