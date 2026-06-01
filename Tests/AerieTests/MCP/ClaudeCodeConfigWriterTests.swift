import XCTest
@testable import Aerie

final class ClaudeCodeConfigWriterTests: XCTestCase {
    private var tmpDir: URL!
    private var tmpPath: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        tmpDir = base.appendingPathComponent("ClaudeCodeConfigWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        tmpPath = tmpDir.appendingPathComponent(".mcp.json")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try FileManager.default.removeItem(at: tmpDir)
        }
    }

    // MARK: - Helpers

    private func readJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: tmpPath)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeRaw(_ json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: tmpPath, options: [.atomic])
    }

    // MARK: - Tests

    func test_defaultPath_targetsClaudeCodeUserConfig() {
        // Claude Code reads user-scope MCP servers from ~/.claude.json (the file
        // shown as "User MCPs" in /mcp). It does NOT read ~/.claude/.mcp.json, so
        // writing there made auto-register a no-op.
        let path = ClaudeCodeConfigWriter.defaultPath()
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(path, home.appendingPathComponent(".claude.json"))
        XCTAssertEqual(path.lastPathComponent, ".claude.json")
        XCTAssertFalse(
            path.path.contains("/.claude/.mcp.json"),
            "must not target the path Claude Code ignores"
        )
    }

    func test_upsertAerie_addsEntry_withoutDisturbingOthers() throws {
        try writeRaw([
            "mcpServers": [
                "linear": ["type": "http", "url": "http://example.com/linear"],
                "github": ["type": "http", "url": "http://example.com/github"],
            ]
        ])

        let writer = ClaudeCodeConfigWriter(path: tmpPath)
        try writer.upsertAerie(endpoint: "http://127.0.0.1:54321/mcp", token: "abc")

        let root = try readJSON()
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertEqual(servers.count, 3)

        let aerie = try XCTUnwrap(servers["aerie"] as? [String: Any])
        XCTAssertEqual(aerie["type"] as? String, "http")
        XCTAssertEqual(aerie["url"] as? String, "http://127.0.0.1:54321/mcp")
        let headers = try XCTUnwrap(aerie["headers"] as? [String: Any])
        XCTAssertEqual(headers["Authorization"] as? String, "Bearer abc")

        // The other servers are still there with their original urls.
        let linear = try XCTUnwrap(servers["linear"] as? [String: Any])
        XCTAssertEqual(linear["url"] as? String, "http://example.com/linear")
        let github = try XCTUnwrap(servers["github"] as? [String: Any])
        XCTAssertEqual(github["url"] as? String, "http://example.com/github")
    }

    func test_removeAerie_skipsWrite_whenAerieAbsent() throws {
        // Hand-written JSON whose float (0.2) and key spacing would change if
        // the file were reserialized through JSONSerialization. With no aerie to
        // remove, the writer must leave the bytes untouched.
        let raw = #"{"mcpServers":{"linear":{"url":"http://example.com","weight":0.2}}}"#
        try raw.data(using: .utf8)!.write(to: tmpPath)
        let before = try Data(contentsOf: tmpPath)

        try ClaudeCodeConfigWriter(path: tmpPath).removeAerie()

        let after = try Data(contentsOf: tmpPath)
        XCTAssertEqual(before, after, "no aerie to remove → file left byte-identical")
    }

    func test_upsertAerie_skipsWrite_whenEntryUnchanged() throws {
        let writer = ClaudeCodeConfigWriter(path: tmpPath)
        try writer.upsertAerie(endpoint: "http://127.0.0.1:5/mcp", token: "t1")
        let before = try Data(contentsOf: tmpPath)

        // Identical endpoint + token → no-op, must not rewrite the file.
        try writer.upsertAerie(endpoint: "http://127.0.0.1:5/mcp", token: "t1")

        let after = try Data(contentsOf: tmpPath)
        XCTAssertEqual(before, after, "unchanged aerie entry → no rewrite")
    }

    func test_upsertAerie_replacesExistingAerie() throws {
        let writer = ClaudeCodeConfigWriter(path: tmpPath)
        try writer.upsertAerie(endpoint: "http://127.0.0.1:1111/mcp", token: "old")
        try writer.upsertAerie(endpoint: "http://127.0.0.1:2222/mcp", token: "new")

        let root = try readJSON()
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertEqual(servers.count, 1)
        let aerie = try XCTUnwrap(servers["aerie"] as? [String: Any])
        XCTAssertEqual(aerie["url"] as? String, "http://127.0.0.1:2222/mcp")
        let headers = try XCTUnwrap(aerie["headers"] as? [String: Any])
        XCTAssertEqual(headers["Authorization"] as? String, "Bearer new")
    }

    func test_removeAerie_leavesOtherEntries() throws {
        try writeRaw([
            "mcpServers": [
                "aerie": ["type": "http", "url": "http://127.0.0.1:1/mcp"],
                "linear": ["type": "http", "url": "http://example.com/linear"],
            ],
            "otherTopLevel": "preserved",
        ])

        let writer = ClaudeCodeConfigWriter(path: tmpPath)
        try writer.removeAerie()

        let root = try readJSON()
        XCTAssertEqual(root["otherTopLevel"] as? String, "preserved")
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNil(servers["aerie"])
        XCTAssertNotNil(servers["linear"])
    }

    func test_removeAerie_isNoop_whenFileMissing() throws {
        let writer = ClaudeCodeConfigWriter(path: tmpPath)
        XCTAssertNoThrow(try writer.removeAerie())
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpPath.path))
    }

    func test_upsertAerie_createsFile_whenAbsent() throws {
        // Use a nested path that doesn't exist yet — upsert must create parent dirs too.
        let nested = tmpDir.appendingPathComponent("deeper").appendingPathComponent(".mcp.json")
        let writer = ClaudeCodeConfigWriter(path: nested)
        try writer.upsertAerie(endpoint: "http://127.0.0.1:9000/mcp", token: "fresh")

        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
        let data = try Data(contentsOf: nested)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        let aerie = try XCTUnwrap(servers["aerie"] as? [String: Any])
        XCTAssertEqual(aerie["url"] as? String, "http://127.0.0.1:9000/mcp")
    }
}
