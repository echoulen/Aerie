import Foundation
import GRDB

/// Data-access object for the `git_status_cache` table.
///
/// Caches the per-repo `LocalGitStatus`. `repo_id` is the primary key,
/// so upserts replace the prior row.
struct GitStatusCacheDAO {
    let dbQueue: DatabaseQueue

    func upsert(_ status: LocalGitStatus) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(status)
        let json = String(data: data, encoding: .utf8)!
        let fetchedAt = Date().timeIntervalSince1970

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO git_status_cache
                    (repo_id, payload_json, fetched_at)
                VALUES (?, ?, ?)
                """,
                arguments: [status.repoId.uuidString, json, fetchedAt]
            )
        }
    }

    func status(forRepo repoId: UUID) async throws -> LocalGitStatus? {
        try await dbQueue.read { db in
            let json = try String.fetchOne(
                db,
                sql: "SELECT payload_json FROM git_status_cache WHERE repo_id = ?",
                arguments: [repoId.uuidString]
            )
            guard let json else { return nil }
            return try JSONDecoder().decode(LocalGitStatus.self, from: Data(json.utf8))
        }
    }
}
