import XCTest
@testable import Aerie

final class LegacyMCPCleanupTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyMCPCleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var config: URL { dir.appendingPathComponent(".claude.json") }
    private var discovery: URL { dir.appendingPathComponent("mcp.json") }
    private var cleanup: LegacyMCPCleanup { LegacyMCPCleanup(claudeConfig: config, discoveryFile: discovery) }

    private func writeConfig(_ object: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: config)
    }

    private func readConfig() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
    }

    func test_removesAerieEntry_keepingOtherServersAndKeys() throws {
        try writeConfig([
            "numStartups": 12,
            "mcpServers": [
                "aerie": ["type": "http", "url": "http://127.0.0.1:1/mcp"],
                "other": ["type": "stdio", "command": "other-mcp"],
            ],
        ])
        cleanup.run()
        let root = try readConfig()
        XCTAssertEqual(root["numStartups"] as? Int, 12)
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNil(servers["aerie"])
        XCTAssertEqual((servers["other"] as? [String: Any])?["command"] as? String, "other-mcp")
    }

    func test_keepsAnEmptiedMCPServersKey() throws {
        try writeConfig(["mcpServers": ["aerie": ["type": "http"]]])
        cleanup.run()
        XCTAssertEqual((try readConfig()["mcpServers"] as? [String: Any])?.isEmpty, true)
    }

    func test_leavesTheConfigUntouched_whenThereIsNoAerieEntry() throws {
        // Compact, unsorted JSON: a rewrite would pretty-print and sort it.
        let original = Data(#"{"z":1,"mcpServers":{"other":{"type":"stdio"}},"a":2}"#.utf8)
        try original.write(to: config)
        cleanup.run()
        XCTAssertEqual(try Data(contentsOf: config), original)
    }

    func test_leavesAnUnparseableConfigUntouched() throws {
        let original = Data("not json".utf8)
        try original.write(to: config)
        cleanup.run()
        XCTAssertEqual(try Data(contentsOf: config), original)
    }

    func test_missingConfig_isANoOp() {
        cleanup.run()
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func test_deletesTheDiscoveryFile() throws {
        try Data(#"{"token":"stale"}"#.utf8).write(to: discovery)
        cleanup.run()
        XCTAssertFalse(FileManager.default.fileExists(atPath: discovery.path))
    }
}
