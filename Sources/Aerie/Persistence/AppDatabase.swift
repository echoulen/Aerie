import GRDB
import Foundation

actor AppDatabase {
    nonisolated let dbQueue: DatabaseQueue

    nonisolated var repos: RepoDAO { RepoDAO(dbQueue: dbQueue) }
    nonisolated var accounts: AccountDAO { AccountDAO(dbQueue: dbQueue) }
    nonisolated var prCache: PRCacheDAO { PRCacheDAO(dbQueue: dbQueue) }
    nonisolated var issueCache: IssueCacheDAO { IssueCacheDAO(dbQueue: dbQueue) }
    nonisolated var prLocalStateCache: PRLocalStateCacheDAO { PRLocalStateCacheDAO(dbQueue: dbQueue) }
    nonisolated var gitStatusCache: GitStatusCacheDAO { GitStatusCacheDAO(dbQueue: dbQueue) }
    nonisolated var mergedBranchCache: MergedBranchCacheDAO { MergedBranchCacheDAO(dbQueue: dbQueue) }
    nonisolated var mcpActivity: MCPActivityDAO { MCPActivityDAO(dbQueue: dbQueue) }
    nonisolated var settings: SettingsDAO { SettingsDAO(dbQueue: dbQueue) }

    static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Aerie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("db.sqlite")
    }

    init(url: URL) throws {
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA foreign_keys = ON") }
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: AppDatabase.schemaV1)
        }
        m.registerMigration("v2") { db in
            try db.execute(sql: AppDatabase.schemaV2)
        }
        m.registerMigration("v3") { db in
            try db.execute(sql: AppDatabase.schemaV3)
        }
        m.registerMigration("v4") { db in
            try db.execute(sql: AppDatabase.schemaV4)
        }
        return m
    }

    static let schemaV1: String = """
    CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        login TEXT NOT NULL,
        host TEXT NOT NULL,
        UNIQUE(login, host)
    );

    CREATE TABLE repos (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        owner TEXT NOT NULL,
        repo TEXT NOT NULL,
        default_branch TEXT NOT NULL DEFAULT 'main',
        account_id TEXT NOT NULL REFERENCES accounts(id),
        sort_order INTEGER NOT NULL DEFAULT 0,
        hidden INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE pr_cache (
        repo_id TEXT NOT NULL REFERENCES repos(id),
        number INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        fetched_at REAL NOT NULL,
        PRIMARY KEY (repo_id, number)
    );

    CREATE TABLE pr_local_state_cache (
        pr_id TEXT PRIMARY KEY,
        repo_id TEXT NOT NULL REFERENCES repos(id),
        payload_json TEXT NOT NULL,
        fetched_at REAL NOT NULL
    );

    CREATE TABLE git_status_cache (
        repo_id TEXT PRIMARY KEY REFERENCES repos(id),
        payload_json TEXT NOT NULL,
        fetched_at REAL NOT NULL
    );

    CREATE TABLE mcp_activity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at REAL NOT NULL,
        agent_id TEXT,
        tool TEXT NOT NULL,
        target TEXT,
        is_write INTEGER NOT NULL DEFAULT 0,
        ok INTEGER NOT NULL,
        error_message TEXT,
        request_json TEXT NOT NULL,
        response_json TEXT NOT NULL
    );

    CREATE INDEX idx_mcp_activity_at ON mcp_activity(at DESC);

    CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    """

    /// v2 — the Issues tab's per-repo cache. Same shape as `pr_cache`: the
    /// whole set of open issues for a repo is replaced on each sync.
    static let schemaV2: String = """
    CREATE TABLE issue_cache (
        repo_id TEXT NOT NULL REFERENCES repos(id),
        number INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        fetched_at REAL NOT NULL,
        PRIMARY KEY (repo_id, number)
    );
    """

    /// v3 — the Repos tab's per-repo "this off-default branch is already merged"
    /// cache. Single row per repo (like `git_status_cache`); replaced or cleared
    /// each detection pass.
    static let schemaV3: String = """
    CREATE TABLE merged_branch_cache (
        repo_id TEXT PRIMARY KEY REFERENCES repos(id),
        payload_json TEXT NOT NULL,
        fetched_at REAL NOT NULL
    );
    """

    /// v4 — per-repo pause switch for the GitHub-hitting sync services (PRs,
    /// Issues, merged-branch check). Local git status refresh is unaffected;
    /// see `PRSyncService`/`IssueSyncService`/`MergedBranchSync`.
    static let schemaV4: String = """
    ALTER TABLE repos ADD COLUMN api_sync_disabled INTEGER NOT NULL DEFAULT 0;
    """
}
