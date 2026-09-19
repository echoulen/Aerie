import XCTest
import GRDB
@testable import Aerie

final class AppDatabaseTests: XCTestCase {
    func test_migratorRunsCleanly() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try AppDatabase(url: url)
        let dbQ = try DatabaseQueue(path: url.path)
        let tables = try dbQ.read { db in try String.fetchAll(db,
            sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") }
        XCTAssertTrue(tables.contains("repos"))
        XCTAssertTrue(tables.contains("accounts"))
        XCTAssertTrue(tables.contains("pr_cache"))
        XCTAssertTrue(tables.contains("issue_cache"))
        XCTAssertTrue(tables.contains("pr_local_state_cache"))
        XCTAssertTrue(tables.contains("git_status_cache"))
        XCTAssertFalse(tables.contains("mcp_activity"), "v5 drops the MCP activity log")
        XCTAssertTrue(tables.contains("settings"))
    }

    /// A database from a build that still had MCP: v5 drops the activity log
    /// and the `mcp.*` settings but keeps every other setting.
    func test_v5_dropsMCPActivityAndSettings() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = try DatabaseQueue(path: url.path)
        try legacy.write { db in
            try db.execute(sql: AppDatabase.schemaV1)
            try db.execute(sql: AppDatabase.schemaV2)
            try db.execute(sql: AppDatabase.schemaV3)
            try db.execute(sql: AppDatabase.schemaV4)
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('v1'), ('v2'), ('v3'), ('v4')")
            try db.execute(sql: """
                INSERT INTO settings (key, value) VALUES
                    ('mcp.auto_register_claude_code', 'true'), ('ai.model', 'claude-sonnet-5')
                """)
        }
        try legacy.close()

        _ = try AppDatabase(url: url)
        let dbQ = try DatabaseQueue(path: url.path)
        let (tables, keys) = try dbQ.read { db in
            (try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'"),
             try String.fetchAll(db, sql: "SELECT key FROM settings ORDER BY key"))
        }
        XCTAssertFalse(tables.contains("mcp_activity"))
        XCTAssertEqual(keys, ["ai.model"])
    }
}
