import Foundation
import GRDB

/// Data-access object for the `accounts` table.
struct AccountDAO {
    let dbQueue: DatabaseQueue

    // MARK: - Writes

    func insert(_ account: GitHubAccount) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [account.id.uuidString, account.login, account.host]
            )
        }
    }

    func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM accounts WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Reads

    func all() async throws -> [GitHubAccount] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM accounts ORDER BY login, host"
            )
            return rows.map(Self.decode)
        }
    }

    func find(login: String, host: String) async throws -> GitHubAccount? {
        try await dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM accounts WHERE login = ? AND host = ?",
                arguments: [login, host]
            )
            return row.map(Self.decode)
        }
    }

    // MARK: - Mapping

    private static func decode(_ row: Row) -> GitHubAccount {
        let idString: String = row["id"]
        return GitHubAccount(
            id: UUID(uuidString: idString)!,
            login: row["login"],
            host: row["host"]
        )
    }
}
