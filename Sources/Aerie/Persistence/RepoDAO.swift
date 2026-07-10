import Foundation
import GRDB

/// Data-access object for the `repos` table.
///
/// Performs explicit column mapping between `Repository` and SQL rows —
/// no `Codable` row persistence, per Phase-2 design.
struct RepoDAO {
    let dbQueue: DatabaseQueue

    // MARK: - Writes

    func insert(_ r: Repository) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO repos (id, name, local_path, owner, repo, default_branch, account_id, sort_order, hidden, api_sync_disabled)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: Self.arguments(for: r)
            )
        }
    }

    func update(_ r: Repository) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE repos
                   SET name = ?,
                       local_path = ?,
                       owner = ?,
                       repo = ?,
                       default_branch = ?,
                       account_id = ?,
                       sort_order = ?,
                       hidden = ?,
                       api_sync_disabled = ?
                 WHERE id = ?
                """,
                arguments: [
                    r.name,
                    r.localPath.path,
                    r.githubOwner,
                    r.githubRepo,
                    r.defaultBranch,
                    r.primaryAccountId.uuidString,
                    r.sortOrder,
                    r.hidden ? 1 : 0,
                    r.apiSyncDisabled ? 1 : 0,
                    r.id.uuidString,
                ]
            )
        }
    }

    /// Deletes a repo and every cache row that references it.
    ///
    /// `foreign_keys` is ON and the child caches (`pr_cache`,
    /// `pr_local_state_cache`, `git_status_cache`, `issue_cache`) reference
    /// `repos(id)` without `ON DELETE CASCADE`, so deleting the repo alone
    /// raises a FOREIGN KEY constraint failure once any cache row exists (the
    /// sync services populate these on the first poll). We clear the children
    /// first, all inside one transaction so a repo never half-deletes.
    func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            for table in ["pr_cache", "pr_local_state_cache", "git_status_cache", "issue_cache"] {
                try db.execute(
                    sql: "DELETE FROM \(table) WHERE repo_id = ?",
                    arguments: [id.uuidString]
                )
            }
            try db.execute(
                sql: "DELETE FROM repos WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func setHidden(id: UUID, _ hidden: Bool) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE repos SET hidden = ? WHERE id = ?",
                arguments: [hidden ? 1 : 0, id.uuidString]
            )
        }
    }

    func setApiSyncDisabled(id: UUID, _ disabled: Bool) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE repos SET api_sync_disabled = ? WHERE id = ?",
                arguments: [disabled ? 1 : 0, id.uuidString]
            )
        }
    }

    func setSortOrder(id: UUID, _ order: Int) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE repos SET sort_order = ? WHERE id = ?",
                arguments: [order, id.uuidString]
            )
        }
    }

    func setName(id: UUID, _ name: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE repos SET name = ? WHERE id = ?",
                arguments: [name, id.uuidString]
            )
        }
    }

    func setAccount(id: UUID, _ accountId: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE repos SET account_id = ? WHERE id = ?",
                arguments: [accountId.uuidString, id.uuidString]
            )
        }
    }

    // MARK: - Reads

    func all() async throws -> [Repository] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM repos ORDER BY sort_order, name"
            )
            return rows.map(Self.decode)
        }
    }

    func find(id: UUID) async throws -> Repository? {
        try await dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM repos WHERE id = ?",
                arguments: [id.uuidString]
            )
            return row.map(Self.decode)
        }
    }

    // MARK: - Mapping

    private static func arguments(for r: Repository) -> StatementArguments {
        [
            r.id.uuidString,
            r.name,
            r.localPath.path,
            r.githubOwner,
            r.githubRepo,
            r.defaultBranch,
            r.primaryAccountId.uuidString,
            r.sortOrder,
            r.hidden ? 1 : 0,
            r.apiSyncDisabled ? 1 : 0,
        ]
    }

    static func decode(_ row: Row) -> Repository {
        let idString: String = row["id"]
        let accountString: String = row["account_id"]
        let hidden: Int = row["hidden"]
        let apiSyncDisabled: Int = row["api_sync_disabled"]
        let localPath: String = row["local_path"]
        return Repository(
            id: UUID(uuidString: idString)!,
            name: row["name"],
            localPath: URL(fileURLWithPath: localPath),
            githubOwner: row["owner"],
            githubRepo: row["repo"],
            defaultBranch: row["default_branch"],
            primaryAccountId: UUID(uuidString: accountString)!,
            sortOrder: row["sort_order"],
            hidden: hidden != 0,
            apiSyncDisabled: apiSyncDisabled != 0
        )
    }
}
