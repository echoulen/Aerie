import Foundation

/// Aerie used to run a local MCP server and advertise it in two places on the
/// user's machine. The server is gone, so on every launch this sweeps both:
///
/// * the `aerie` entry under `mcpServers` in `~/.claude.json` (Claude Code's
///   user-scope config) — left behind, Claude Code keeps trying to reach a dead
///   endpoint;
/// * the discovery file `~/Library/Application Support/Aerie/mcp.json`, which
///   carries a stale bearer token.
///
/// Both steps are idempotent and leave everything else alone: once the entries
/// are gone, a launch only reads `~/.claude.json` and never rewrites it.
struct LegacyMCPCleanup {
    let claudeConfig: URL
    let discoveryFile: URL

    init(
        claudeConfig: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json"),
        discoveryFile: URL = AppDatabase.defaultURL()
            .deletingLastPathComponent()
            .appendingPathComponent("mcp.json")
    ) {
        self.claudeConfig = claudeConfig
        self.discoveryFile = discoveryFile
    }

    func run() {
        do {
            try removeClaudeConfigEntry()
        } catch {
            NSLog("Legacy MCP cleanup: couldn't update \(claudeConfig.path): \(error)")
        }
        try? FileManager.default.removeItem(at: discoveryFile)
    }

    /// Drops `mcpServers.aerie`. Every other key — including other servers and
    /// an emptied `mcpServers` — is kept. No-op (no rewrite) when the file,
    /// `mcpServers` or the entry is missing, or the file isn't a JSON object.
    func removeClaudeConfigEntry() throws {
        guard let data = try? Data(contentsOf: claudeConfig),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var servers = root["mcpServers"] as? [String: Any],
              servers["aerie"] != nil
        else { return }
        servers.removeValue(forKey: "aerie")
        root["mcpServers"] = servers
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        // ~/.claude.json is Claude Code's own config — never leave it missing:
        // `replaceItemAt` keeps the original until the new file is in place.
        let tmp = claudeConfig.appendingPathExtension("aerie-tmp")
        try? FileManager.default.removeItem(at: tmp)
        try out.write(to: tmp, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(claudeConfig, withItemAt: tmp)
    }
}
