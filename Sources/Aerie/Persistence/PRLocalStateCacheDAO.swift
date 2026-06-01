import Foundation
import GRDB

/// Data-access object for the `pr_local_state_cache` table.
///
/// Caches the locally-computed `PRLocalState` keyed by the PR's UUID.
/// `repoId` is passed in for FK and bulk-clear convenience (the model
/// itself doesn't carry the repo id).
struct PRLocalStateCacheDAO {
    let dbQueue: DatabaseQueue

    func upsert(_ state: PRLocalState, repoId: UUID) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let json = String(data: data, encoding: .utf8)!
        let fetchedAt = Date().timeIntervalSince1970

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO pr_local_state_cache
                    (pr_id, repo_id, payload_json, fetched_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [state.prId.uuidString, repoId.uuidString, json, fetchedAt]
            )
        }
    }

    func state(forPr prId: UUID) async throws -> PRLocalState? {
        try await dbQueue.read { db in
            let json = try String.fetchOne(
                db,
                sql: "SELECT payload_json FROM pr_local_state_cache WHERE pr_id = ?",
                arguments: [prId.uuidString]
            )
            guard let json else { return nil }
            return try JSONDecoder().decode(PRLocalState.self, from: Data(json.utf8))
        }
    }
}
