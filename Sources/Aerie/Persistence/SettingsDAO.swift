import Foundation
import GRDB

/// Data-access object for the `settings` key-value table.
///
/// Stores all values as TEXT. Typed helpers (`setBool`/`getBool`, etc.)
/// convert to/from the string representation.
struct SettingsDAO {
    let dbQueue: DatabaseQueue

    // MARK: - Raw

    func set(_ key: String, _ json: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arguments: [key, json]
            )
        }
    }

    func get(_ key: String) async throws -> String? {
        try await dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }

    /// Removes `key` entirely (vs. writing an empty value), so `get` returns
    /// nil and callers fall back to their built-in default. No-op when absent.
    func delete(_ key: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }

    // MARK: - Bool

    func setBool(_ key: String, _ value: Bool) async throws {
        try await set(key, value ? "true" : "false")
    }

    func getBool(_ key: String) async throws -> Bool? {
        guard let raw = try await get(key) else { return nil }
        switch raw {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    // MARK: - Int

    func setInt(_ key: String, _ value: Int) async throws {
        try await set(key, String(value))
    }

    func getInt(_ key: String) async throws -> Int? {
        guard let raw = try await get(key) else { return nil }
        return Int(raw)
    }

    // MARK: - String

    func setString(_ key: String, _ value: String) async throws {
        try await set(key, value)
    }

    func getString(_ key: String) async throws -> String? {
        try await get(key)
    }
}
