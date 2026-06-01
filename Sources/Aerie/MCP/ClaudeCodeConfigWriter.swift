import Foundation

/// Writes/removes Aerie's entry inside `~/.claude.json` (Claude Code's
/// user-scope config — the "User MCPs" list in `/mcp`) so Claude Code can
/// auto-discover the local MCP server. Phase 20 supersedes the discovery file
/// for the Claude Code integration — though `DiscoveryFileWriter` is still kept
/// for other MCP clients.
///
/// NOTE: the target is `~/.claude.json`, NOT `~/.claude/.mcp.json`. Claude Code
/// does not read the latter, so writing there made auto-register a silent no-op.
///
/// **Preservation:** all top-level keys outside `mcpServers` are copied
/// verbatim, and the rest of `mcpServers` (entries other than `aerie`) is left
/// untouched.
///
/// **Ordering tradeoff:** `JSONSerialization` doesn't preserve key insertion
/// order. With `.sortedKeys`, we produce a deterministic alphabetical layout —
/// user-edited entries may get reordered, but their *contents* are preserved
/// verbatim. The Claude Code config is small enough that this is acceptable.
///
/// **Atomicity:** we write to `<path>.tmp`, then `moveItem` (rename(2)) — same
/// pattern as `DiscoveryFileWriter`.
struct ClaudeCodeConfigWriter {
    let path: URL

    /// `~/.claude.json` — Claude Code's user-scope config. Parent directory
    /// (the home dir) always exists; the upsert path still creates intermediate
    /// dirs defensively so tests can point at nested temp URLs.
    static func defaultPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude.json")
    }

    init(path: URL = ClaudeCodeConfigWriter.defaultPath()) {
        self.path = path
    }

    /// Adds (or replaces) the `aerie` entry under `mcpServers`. Creates the
    /// file (and parent directory) if missing. Other servers under
    /// `mcpServers` and other top-level keys are preserved verbatim.
    func upsertAerie(endpoint: String, token: String) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var root: [String: Any] = readOrEmpty()
        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        let desired: [String: Any] = [
            "type": "http",
            "url": endpoint,
            "headers": ["Authorization": "Bearer \(token)"]
        ]
        // No-op guard: skip the rewrite when our entry is already current.
        // Reserializing ~/.claude.json reformats every float to full IEEE-754
        // precision, so we only touch the file when aerie actually changes.
        if let existing = servers["aerie"] as? [String: Any],
           existing["type"] as? String == "http",
           existing["url"] as? String == endpoint,
           (existing["headers"] as? [String: Any])?["Authorization"] as? String
            == "Bearer \(token)" {
            return
        }
        servers["aerie"] = desired
        root["mcpServers"] = servers
        try atomicWrite(root)
    }

    /// Removes the `aerie` entry if present. Leaves all other entries — and
    /// the `mcpServers` key itself, even if empty — intact. No-op if the file
    /// doesn't exist.
    func removeAerie() throws {
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        var root: [String: Any] = readOrEmpty()
        guard var servers = root["mcpServers"] as? [String: Any] else { return }
        // No-op guard: nothing to remove → don't rewrite (and reformat) the file.
        guard servers["aerie"] != nil else { return }
        servers.removeValue(forKey: "aerie")
        root["mcpServers"] = servers
        try atomicWrite(root)
    }

    private func readOrEmpty() -> [String: Any] {
        guard
            let data = try? Data(contentsOf: path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private func atomicWrite(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        let tmp = path.appendingPathExtension("tmp")
        if FileManager.default.fileExists(atPath: tmp.path) {
            try FileManager.default.removeItem(at: tmp)
        }
        try data.write(to: tmp, options: [.atomic])
        // ~/.claude.json is Claude Code's own config — never leave it missing.
        // `replaceItemAt` swaps atomically (the original survives until the
        // replacement is in place); `moveItem` only handles the first-write case
        // where there's nothing to replace yet.
        if FileManager.default.fileExists(atPath: path.path) {
            _ = try FileManager.default.replaceItemAt(path, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: path)
        }
    }
}
