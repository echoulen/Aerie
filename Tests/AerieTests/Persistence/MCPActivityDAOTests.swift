import XCTest
import GRDB
@testable import Aerie

final class MCPActivityDAOTests: XCTestCase {
    // MARK: - Helpers

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

    private func makeRecord(
        at: Date = Date(),
        tool: String = "git.status",
        ok: Bool = true,
        isWrite: Bool = false
    ) -> MCPActivityRecord {
        MCPActivityRecord(
            id: nil,
            at: at,
            agentId: "agent-x",
            tool: tool,
            target: "/tmp/example",
            isWrite: isWrite,
            ok: ok,
            errorMessage: ok ? nil : "boom",
            requestJSON: "{}",
            responseJSON: "{}"
        )
    }

    // MARK: - Tests

    func test_insert_thenRecent() async throws {
        let db = try makeDB()
        let r = makeRecord(tool: "git.status")
        try await db.mcpActivity.insert(r)

        let recent = try await db.mcpActivity.recent(limit: 10)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.tool, "git.status")
        XCTAssertNotNil(recent.first?.id)
    }

    func test_recent_respectsLimit() async throws {
        let db = try makeDB()
        for i in 0..<5 {
            try await db.mcpActivity.insert(
                makeRecord(at: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)), tool: "tool\(i)")
            )
        }

        let recent = try await db.mcpActivity.recent(limit: 3)
        XCTAssertEqual(recent.count, 3)
    }

    func test_recent_orderedByAtDesc() async throws {
        let db = try makeDB()
        let base = 1_700_000_000.0
        try await db.mcpActivity.insert(makeRecord(at: Date(timeIntervalSince1970: base + 1), tool: "first"))
        try await db.mcpActivity.insert(makeRecord(at: Date(timeIntervalSince1970: base + 3), tool: "third"))
        try await db.mcpActivity.insert(makeRecord(at: Date(timeIntervalSince1970: base + 2), tool: "second"))

        let recent = try await db.mcpActivity.recent(limit: 10)
        XCTAssertEqual(recent.map { $0.tool }, ["third", "second", "first"])
    }

    func test_all_orderedByAtDesc() async throws {
        let db = try makeDB()
        let base = 1_700_000_000.0
        try await db.mcpActivity.insert(makeRecord(at: Date(timeIntervalSince1970: base + 5), tool: "newer"))
        try await db.mcpActivity.insert(makeRecord(at: Date(timeIntervalSince1970: base + 1), tool: "older"))

        let all = try await db.mcpActivity.all()
        XCTAssertEqual(all.map { $0.tool }, ["newer", "older"])
    }

    func test_insert_trimsTo1000_whenOverThreshold() async throws {
        let db = try makeDB()
        let base = 1_700_000_000.0
        // Insert 1010 records, each at a unique increasing timestamp.
        for i in 0..<1010 {
            try await db.mcpActivity.insert(
                makeRecord(at: Date(timeIntervalSince1970: base + Double(i)), tool: "t\(i)")
            )
        }

        let count = try await db.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mcp_activity") ?? 0
        }
        XCTAssertEqual(count, 1000)

        // The surviving rows should be the most recent 1000 — i.e. tools t10..t1009.
        let all = try await db.mcpActivity.all()
        XCTAssertEqual(all.count, 1000)
        XCTAssertEqual(all.first?.tool, "t1009") // newest
        XCTAssertEqual(all.last?.tool, "t10")    // oldest surviving
    }
}
