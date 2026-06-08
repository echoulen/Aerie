import Foundation
import GRDB

/// Data-access object for the `merged_branch_cache` table.
///
/// Caches the per-repo `MergedBranchInfo`. `repo_id` is the primary key, so
/// upserts replace the prior row. `clear(forRepo:)` drops the entry when the
/// repo is back on its default branch or no longer has a merged PR for the
/// checked-out branch.
struct MergedBranchCacheDAO {
    let dbQueue: DatabaseQueue

    func upsert(_ info: MergedBranchInfo) async throws {
        let data = try JSONEncoder().encode(info)
        let json = String(data: data, encoding: .utf8)!
        let fetchedAt = Date().timeIntervalSince1970
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO merged_branch_cache
                    (repo_id, payload_json, fetched_at)
                VALUES (?, ?, ?)
                """,
                arguments: [info.repoId.uuidString, json, fetchedAt]
            )
        }
    }

    func info(forRepo repoId: UUID) async throws -> MergedBranchInfo? {
        try await dbQueue.read { db in
            let json = try String.fetchOne(
                db,
                sql: "SELECT payload_json FROM merged_branch_cache WHERE repo_id = ?",
                arguments: [repoId.uuidString]
            )
            guard let json else { return nil }
            return try JSONDecoder().decode(MergedBranchInfo.self, from: Data(json.utf8))
        }
    }

    func clear(forRepo repoId: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM merged_branch_cache WHERE repo_id = ?",
                arguments: [repoId.uuidString]
            )
        }
    }
}
