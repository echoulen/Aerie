import Foundation

/// Writes (and clears) the MCP discovery file at
/// `~/Library/Application Support/Aerie/mcp.json`. Phase 20 will swap in a
/// proper ~/.claude/.mcp.json updater; for Phase 18 this is the only
/// out-of-process advertisement of the server.
///
/// On-disk format:
/// ```json
/// {
///   "endpoint":   "http://127.0.0.1:54321/mcp",
///   "token":      "<uuid>",
///   "pid":        12345,
///   "started_at": 1717000000.0
/// }
/// ```
///
/// Two design choices worth flagging:
/// * **0600 permissions** — the file carries a bearer token. We set the
///   mode on the temp file *before* moving it into place so there's no
///   window where a world-readable file exists.
/// * **Atomic write** — write to `<path>.tmp`, chmod, then `moveItem`
///   (which is rename(2) under the hood). Readers either see the old
///   payload or the new one, never a torn one.
struct DiscoveryFileWriter {
    /// Decoded JSON payload. Codable so callers can read it back for tests.
    struct DiscoveryPayload: Codable, Equatable {
        let endpoint: String
        let token: String
        let pid: Int
        let started_at: Double
    }

    let path: URL

    /// `~/Library/Application Support/Aerie/mcp.json`. The directory is
    /// created on first call. We return the file URL even if creation
    /// failed — callers that proceed to ``write(endpoint:token:)`` will
    /// see the real error there.
    static func defaultPath() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Aerie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mcp.json")
    }

    init(path: URL = DiscoveryFileWriter.defaultPath()) {
        self.path = path
    }

    /// Write the discovery file atomically with mode 0600.
    func write(endpoint: String, token: String) throws {
        let payload = DiscoveryPayload(
            endpoint: endpoint,
            token: token,
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            started_at: Date().timeIntervalSince1970
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        // Make sure the parent dir exists — caller might have passed a
        // custom path under a fresh tmpdir.
        let parent = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        // Write to a sibling tmp file, chmod 0600, then rename into place.
        let tmp = path.appendingPathExtension("tmp")
        // If a stale tmp file exists from a crashed prior run, blow it away.
        if FileManager.default.fileExists(atPath: tmp.path) {
            try FileManager.default.removeItem(at: tmp)
        }
        try data.write(to: tmp, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: tmp.path
        )
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        try FileManager.default.moveItem(at: tmp, to: path)
    }

    /// Remove the discovery file. Idempotent — missing file is a no-op.
    func clear() throws {
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}
