import Foundation
import Observation
import AppKit

/// View model for Settings → MCP.
///
/// Dependencies are injected as closures so tests can drive the screen with
/// a stub server. The actor-isolated `MCPServer` is wrapped at the call site
/// (in `AerieApp`) — the VM only sees a `ServerStatus` snapshot.
@Observable
@MainActor
final class MCPSettingsViewModel {
    struct ServerStatus: Equatable {
        let running: Bool
        let pid: Int
        let uptimeSeconds: TimeInterval?
        let endpoint: URL?

        static let stopped = ServerStatus(running: false, pid: 0, uptimeSeconds: nil, endpoint: nil)
    }

    private(set) var status: ServerStatus = .stopped
    private(set) var token: String = ""
    private(set) var tokenRevealed: Bool = false
    private(set) var autoRegisterOn: Bool = false
    private(set) var recentActivity: [MCPActivityRecord] = []
    let discoveryFilePath: URL

    private let db: AppDatabase
    private let serverStatusProvider: () async -> ServerStatus
    private let tokenProvider: () async -> String
    private let rotateTokenAction: () async -> Void
    private let runConfigUpsert: () async -> Void
    private let runConfigRemove: () async -> Void

    init(
        db: AppDatabase,
        discoveryFilePath: URL = DiscoveryFileWriter.defaultPath(),
        serverStatus: @escaping () async -> ServerStatus,
        tokenProvider: @escaping () async -> String,
        rotateToken: @escaping () async -> Void,
        runConfigUpsert: @escaping () async -> Void,
        runConfigRemove: @escaping () async -> Void
    ) {
        self.db = db
        self.discoveryFilePath = discoveryFilePath
        self.serverStatusProvider = serverStatus
        self.tokenProvider = tokenProvider
        self.rotateTokenAction = rotateToken
        self.runConfigUpsert = runConfigUpsert
        self.runConfigRemove = runConfigRemove
    }

    func refresh() async {
        status = await serverStatusProvider()
        token = await tokenProvider()
        recentActivity = (try? await db.mcpActivity.recent(limit: 6)) ?? []
        if let stored = try? await db.settings.getBool("mcp.auto_register_claude_code") {
            autoRegisterOn = stored
        }
    }

    func revealToken() { tokenRevealed = true }
    func hideToken() { tokenRevealed = false }

    func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
    }

    func copyEndpoint() {
        guard let endpoint = status.endpoint else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(endpoint.absoluteString, forType: .string)
    }

    func revealDiscoveryFileInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([discoveryFilePath])
    }

    func rotateNow() async {
        await rotateTokenAction()
        await refresh()
    }

    func setAutoRegister(_ on: Bool) async {
        autoRegisterOn = on
        try? await db.settings.setBool("mcp.auto_register_claude_code", on)
        if on { await runConfigUpsert() } else { await runConfigRemove() }
    }

    /// Token rendered for display: masked when `tokenRevealed == false`.
    var displayedToken: String {
        if tokenRevealed { return token }
        guard !token.isEmpty else { return "" }
        // Show the first 4 chars then the standard "aer_••••" style mask so
        // the user can recognize the prefix without exposing the secret.
        let prefix = String(token.prefix(4))
        return "\(prefix)••••••••••••••••"
    }

    /// Best-effort "2h 14m" formatting. Hidden when uptime is nil.
    var uptimeLabel: String? {
        guard let s = status.uptimeSeconds else { return nil }
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
