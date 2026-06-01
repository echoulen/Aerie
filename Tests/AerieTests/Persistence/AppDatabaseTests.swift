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
        XCTAssertTrue(tables.contains("mcp_activity"))
        XCTAssertTrue(tables.contains("settings"))
    }
}
