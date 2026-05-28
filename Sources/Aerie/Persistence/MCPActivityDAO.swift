import Foundation
import GRDB

/// Data-access object for the `mcp_activity` audit-log table.
///
/// On each `insert`, prunes the table back to the most recent 1000 rows.
struct MCPActivityDAO {
    static let retentionLimit = 1000

    let dbQueue: DatabaseQueue

    // MARK: - Writes

    func insert(_ record: MCPActivityRecord) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO mcp_activity
                    (at, agent_id, tool, target, is_write, ok, error_message, request_json, response_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.at.timeIntervalSince1970,
                    record.agentId,
                    record.tool,
                    record.target,
                    record.isWrite ? 1 : 0,
                    record.ok ? 1 : 0,
                    record.errorMessage,
                    record.requestJSON,
                    record.responseJSON,
                ]
            )

            // Trim to the most recent `retentionLimit` rows by id.
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mcp_activity") ?? 0
            if count > Self.retentionLimit {
                let excess = count - Self.retentionLimit
                try db.execute(
                    sql: """
                    DELETE FROM mcp_activity
                    WHERE id IN (SELECT id FROM mcp_activity ORDER BY id ASC LIMIT ?)
                    """,
                    arguments: [excess]
                )
            }
        }
    }

    // MARK: - Reads

    func recent(limit: Int) async throws -> [MCPActivityRecord] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM mcp_activity ORDER BY at DESC LIMIT ?",
                arguments: [limit]
            )
            return rows.map(Self.decode)
        }
    }

    func all() async throws -> [MCPActivityRecord] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM mcp_activity ORDER BY at DESC")
            return rows.map(Self.decode)
        }
    }

    // MARK: - Mapping

    private static func decode(_ row: Row) -> MCPActivityRecord {
        let atRaw: Double = row["at"]
        let isWrite: Int = row["is_write"]
        let ok: Int = row["ok"]
        return MCPActivityRecord(
            id: row["id"],
            at: Date(timeIntervalSince1970: atRaw),
            agentId: row["agent_id"],
            tool: row["tool"],
            target: row["target"],
            isWrite: isWrite != 0,
            ok: ok != 0,
            errorMessage: row["error_message"],
            requestJSON: row["request_json"],
            responseJSON: row["response_json"]
        )
    }
}
