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
