import XCTest
import GRDB
@testable import Aerie

final class ActivityLoggerTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    // MARK: - Direct logger tests

    func test_record_insertsRow() async throws {
        let db = try makeDB()
        let logger = ActivityLogger(db: db)
        await logger.record(
            agentId: "claude",
            tool: "aerie_list_repos",
            target: nil,
            isWrite: false,
            ok: true,
            errorMessage: nil,
            requestJSON: "{}",
            responseJSON: "{}"
        )
        let rows = try await db.mcpActivity.recent(limit: 10)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.tool, "aerie_list_repos")
        XCTAssertEqual(rows.first?.agentId, "claude")
        XCTAssertEqual(rows.first?.isWrite, false)
        XCTAssertEqual(rows.first?.ok, true)
    }

    // MARK: - Router integration tests

    func test_dispatch_recordsActivityRow_forToolCall() async throws {
        let db = try makeDB()
        let registry = MCPToolRegistry()
        await registry.register(ListReposTool(db: db))
        let logger = ActivityLogger(db: db)

        let router = JSONRPCRouter()
        await router.register("tools/call") { params in
            try await registry.dispatch(params: params)
        }

        let request = JSONRPCRequest(
            jsonrpc: "2.0", id: .int(1), method: "tools/call",
            params: .object([
                "name": .string("aerie_list_repos"),
                "arguments": .object([:]),
            ])
        )
        let rawJSON = try String(
            data: JSONEncoder().encode(request), encoding: .utf8
        )!
        let resp = await router.dispatchWithLogging(
            request,
            rawRequestJSON: rawJSON,
            agentId: "test-agent",
            registry: registry,
            logger: logger
        )
        XCTAssertNil(resp.error)

        let activity = try await db.mcpActivity.recent(limit: 10)
        XCTAssertEqual(activity.count, 1)
        XCTAssertEqual(activity.first?.tool, "aerie_list_repos")
        XCTAssertEqual(activity.first?.agentId, "test-agent")
        XCTAssertEqual(activity.first?.isWrite, false)
        XCTAssertEqual(activity.first?.ok, true)
        XCTAssertNil(activity.first?.errorMessage)
    }

    func test_dispatch_recordsFailingToolCall_withErrorMessage() async throws {
        let db = try makeDB()
        let registry = MCPToolRegistry()
        // GetLocalStatusTool throws on missing repo_id with -32602.
        await registry.register(GetLocalStatusTool(db: db))
        let logger = ActivityLogger(db: db)

        let router = JSONRPCRouter()
        await router.register("tools/call") { params in
            try await registry.dispatch(params: params)
        }

        let request = JSONRPCRequest(
            jsonrpc: "2.0", id: .int(2), method: "tools/call",
            params: .object([
                "name": .string("aerie_get_local_status"),
                "arguments": .object([:]),
            ])
        )
        let rawJSON = try String(
            data: JSONEncoder().encode(request), encoding: .utf8
        )!
        let resp = await router.dispatchWithLogging(
            request,
            rawRequestJSON: rawJSON,
            agentId: nil,
            registry: registry,
            logger: logger
        )
        XCTAssertEqual(resp.error?.code, -32602)

        let activity = try await db.mcpActivity.recent(limit: 10)
        XCTAssertEqual(activity.count, 1)
        XCTAssertEqual(activity.first?.tool, "aerie_get_local_status")
        XCTAssertEqual(activity.first?.ok, false)
        XCTAssertNotNil(activity.first?.errorMessage)
        XCTAssertNil(activity.first?.agentId)
    }

    func test_dispatch_captures_writeFlag_andTarget() async throws {
        let db = try makeDB()
        // Tool with isWrite=true. We don't need it to succeed — just to be
        // looked up so the registry reports its isWrite.
        let registry = MCPToolRegistry()
        let stub = StubGitHubAPIClient()
        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [:] },
            accountsInOrder: { [] }
        )
        await registry.register(MergePRTool(db: db, api: api, refresh: { _ in }))
        let logger = ActivityLogger(db: db)

        let router = JSONRPCRouter()
        await router.register("tools/call") { params in
            try await registry.dispatch(params: params)
        }

        let repoId = UUID()
        let request = JSONRPCRequest(
            jsonrpc: "2.0", id: .int(3), method: "tools/call",
            params: .object([
                "name": .string("aerie_merge_pr"),
                "arguments": .object([
                    "repo_id": .string(repoId.uuidString),
                    "number": .int(1),
                ]),
            ])
        )
        let rawJSON = try String(
            data: JSONEncoder().encode(request), encoding: .utf8
        )!
        _ = await router.dispatchWithLogging(
            request,
            rawRequestJSON: rawJSON,
            agentId: "agent-x",
            registry: registry,
            logger: logger
        )

        let activity = try await db.mcpActivity.recent(limit: 10)
        XCTAssertEqual(activity.count, 1)
        XCTAssertEqual(activity.first?.tool, "aerie_merge_pr")
        XCTAssertEqual(activity.first?.isWrite, true)
        XCTAssertEqual(activity.first?.target, "repo:\(repoId.uuidString)")
    }

    // MARK: - Full server integration

    func test_server_loggingPath_recordsActivityWithAgentHeader() async throws {
        let db = try makeDB()
        let registry = MCPToolRegistry()
        await registry.register(ListReposTool(db: db))
        let logger = ActivityLogger(db: db)

        let router = JSONRPCRouter()
        await router.register("tools/call") { params in
            try await registry.dispatch(params: params)
        }

        let server = MCPServer(router: router, registry: registry, logger: logger)
        try await server.start()
        defer { Task { await server.stop() } }

        guard let endpoint = await server.endpoint,
              let token = await server.token else {
            XCTFail("server did not start")
            return
        }

        let body = try JSONEncoder().encode(JSONRPCRequest(
            id: .int(1),
            method: "tools/call",
            params: .object([
                "name": .string("aerie_list_repos"),
                "arguments": .object([:]),
            ])
        ))
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("integration-agent", forHTTPHeaderField: "X-MCP-Agent-Id")

        let (_, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        // Logging happens after the response is built — give the actor a
        // moment to flush, then poll the table.
        var rows: [MCPActivityRecord] = []
        for _ in 0..<50 {
            rows = try await db.mcpActivity.recent(limit: 10)
            if !rows.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.tool, "aerie_list_repos")
        XCTAssertEqual(rows.first?.agentId, "integration-agent")
    }

    func test_server_missingAgentHeader_logsUnknown() async throws {
        let db = try makeDB()
        let registry = MCPToolRegistry()
        await registry.register(ListReposTool(db: db))
        let logger = ActivityLogger(db: db)

        let router = JSONRPCRouter()
        await router.register("tools/call") { params in
            try await registry.dispatch(params: params)
        }

        let server = MCPServer(router: router, registry: registry, logger: logger)
        try await server.start()
        defer { Task { await server.stop() } }

        guard let endpoint = await server.endpoint,
              let token = await server.token else {
            XCTFail("server did not start")
            return
        }

        let body = try JSONEncoder().encode(JSONRPCRequest(
            id: .int(1),
            method: "tools/call",
            params: .object([
                "name": .string("aerie_list_repos"),
                "arguments": .object([:]),
            ])
        ))
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        _ = try await URLSession.shared.data(for: req)

        var rows: [MCPActivityRecord] = []
        for _ in 0..<50 {
            rows = try await db.mcpActivity.recent(limit: 10)
            if !rows.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.agentId, "unknown")
    }

    func test_dispatch_nonToolsCall_doesNotLog() async throws {
        let db = try makeDB()
        let registry = MCPToolRegistry()
        let logger = ActivityLogger(db: db)

        let router = JSONRPCRouter()
        await router.register("tools/list") { _ in
            .object(["tools": .array([])])
        }

        let request = JSONRPCRequest(
            jsonrpc: "2.0", id: .int(4), method: "tools/list",
            params: nil
        )
        let rawJSON = try String(
            data: JSONEncoder().encode(request), encoding: .utf8
        )!
        let resp = await router.dispatchWithLogging(
            request,
            rawRequestJSON: rawJSON,
            agentId: "x",
            registry: registry,
            logger: logger
        )
        XCTAssertNil(resp.error)

        let activity = try await db.mcpActivity.recent(limit: 10)
        XCTAssertTrue(activity.isEmpty)
    }
}
