import Foundation
import GRDB

/// Data-access object for the `issue_cache` table.
///
/// Stores the per-repo set of `Issue` records as JSON payloads. Each
/// `upsert(_:for:)` replaces the entire set of rows for the given repo within a
/// single transaction. Mirrors ``PRCacheDAO`` exactly.
struct IssueCacheDAO {
    let dbQueue: DatabaseQueue

    // MARK: - Writes

    func upsert(_ issues: [Issue], for repoId: UUID) async throws {
        let fetchedAt = Date().timeIntervalSince1970
        let encoder = JSONEncoder()
        let payloads: [(Int, String)] = try issues.map { issue in
            let data = try encoder.encode(issue)
            let json = String(data: data, encoding: .utf8)!
            return (issue.number, json)
        }

        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM issue_cache WHERE repo_id = ?",
                arguments: [repoId.uuidString]
            )
            for (number, json) in payloads {
                try db.execute(
                    sql: """
                    INSERT INTO issue_cache (repo_id, number, payload_json, fetched_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [repoId.uuidString, number, json, fetchedAt]
                )
            }
        }
    }

    func clear(forRepo repoId: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM issue_cache WHERE repo_id = ?",
                arguments: [repoId.uuidString]
            )
        }
    }

    // MARK: - Reads

    func issues(forRepo repoId: UUID) async throws -> [Issue] {
        try await dbQueue.read { db in
            let payloads = try String.fetchAll(
                db,
                sql: "SELECT payload_json FROM issue_cache WHERE repo_id = ? ORDER BY number",
                arguments: [repoId.uuidString]
            )
            let decoder = JSONDecoder()
            return try payloads.map { json in
                try decoder.decode(Issue.self, from: Data(json.utf8))
            }
        }
    }
}
