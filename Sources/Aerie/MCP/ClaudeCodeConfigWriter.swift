import Foundation

/// Writes/removes Aerie's entry inside `~/.claude/.mcp.json` so Claude Code can
/// auto-discover the local MCP server. Phase 20 supersedes the discovery file
/// for the Claude Code integration — though `DiscoveryFileWriter` is still kept
/// for other MCP clients.
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

    /// `~/.claude/.mcp.json`. Parent directory is created on demand by the
    /// upsert path; we don't pre-create it here so tests can use temp URLs.
    static func defaultPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/.mcp.json")
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
        servers["aerie"] = [
            "type": "http",
            "url": endpoint,
            "headers": ["Authorization": "Bearer \(token)"]
        ] as [String: Any]
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
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        try FileManager.default.moveItem(at: tmp, to: path)
    }
}
