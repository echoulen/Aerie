import AppKit
import Foundation
import Observation

/// Owns the phone backend's lifecycle and the state the Settings · Mobile
/// screen shows: the on/off switch, the server status, the Tailscale address
/// and the paired devices.
@MainActor
@Observable
final class MobileController {
    static let enabledKey = "mobile.enabled"
    static let portKey = "mobile.port"
    /// The tailnet HTTPS port Aerie is published on. vision-claude already
    /// owns `:443 /` on this Mac, so Aerie takes its own port.
    nonisolated static let tailscalePort = 8443

    enum ServerState: Equatable {
        case off
        case starting
        case running(port: Int)
        case failed(String)
    }

    /// What `tailscale serve status --json` says about Aerie's mapping.
    enum TailscaleState: Equatable {
        case unknown
        case notInstalled
        /// Tailscale runs, but nothing maps `:8443` to Aerie's port yet.
        case notServing(host: String?)
        case serving(url: URL)
        /// `:8443` is mapped somewhere else.
        case conflict(host: String, target: String)
    }

    private(set) var enabled = false
    private(set) var port = MobileServer.defaultPort
    private(set) var server: ServerState = .off
    private(set) var tailscale: TailscaleState = .unknown
    private(set) var devices: [MobileDevice] = []

    private unowned let services: AppServices
    @ObservationIgnored private lazy var bridge = MobileBridge(services: services)
    @ObservationIgnored private lazy var auth = MobileAuth(
        approver: { name, client in await MobilePairApproval.ask(deviceName: name, client: client) },
        onDevicesChanged: { [weak self] in Task { @MainActor in await self?.reloadDevices() } })
    @ObservationIgnored private var httpServer: MobileServer?

    init(services: AppServices) { self.services = services }

    /// Reads the persisted switch and starts the server if it's on. Call once
    /// at launch.
    func bootstrap() async {
        enabled = ((try? await services.db.settings.getBool(Self.enabledKey)) ?? nil) ?? false
        port = ((try? await services.db.settings.getInt(Self.portKey)) ?? nil) ?? MobileServer.defaultPort
        await reloadDevices()
        if enabled { await startServer() }
    }

    func setEnabled(_ on: Bool) async {
        enabled = on
        try? await services.db.settings.setBool(Self.enabledKey, on)
        if on { await startServer() } else { await stopServer() }
        await refreshTailscale()
    }

    func revoke(_ device: MobileDevice) async {
        await auth.revoke(device.id)
        await reloadDevices()
    }

    func reloadDevices() async {
        devices = await auth.allDevices()
    }

    /// The command that publishes Aerie on the tailnet without touching other
    /// mappings (never the bare `tailscale serve --bg <port>`, which would
    /// replace vision-claude's root mapping).
    var serveCommand: String { "tailscale serve --bg --https=\(Self.tailscalePort) \(port)" }

    // MARK: Server

    private func startServer() async {
        if httpServer != nil { return }
        server = .starting
        let s = MobileServer(auth: auth, bridge: bridge)
        do {
            try await s.start(port: port)
            httpServer = s
            server = .running(port: port)
        } catch {
            server = .failed("Couldn't listen on 127.0.0.1:\(port) — \(error.localizedDescription)")
        }
    }

    private func stopServer() async {
        await httpServer?.stop()
        httpServer = nil
        server = .off
    }

    // MARK: Tailscale

    func refreshTailscale() async {
        let port = self.port
        tailscale = await Task.detached { Self.probeTailscale(aeriePort: port) }.value
    }

    nonisolated static let tailscaleCandidates = [
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    nonisolated private static func probeTailscale(aeriePort: Int) -> TailscaleState {
        guard let cli = tailscaleCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .notInstalled
        }
        let host = run(cli, ["status", "--json"])
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { ($0["Self"] as? [String: Any])?["DNSName"] as? String }
            .map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        let serve = run(cli, ["serve", "status", "--json"])
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return interpret(serve: serve, host: host, aeriePort: aeriePort)
    }

    /// Pure reading of `tailscale serve status --json` (split out for tests).
    nonisolated static func interpret(serve: [String: Any]?, host: String?, aeriePort: Int) -> TailscaleState {
        guard let host else { return .notServing(host: nil) }
        let key = "\(host):\(tailscalePort)"
        guard let web = serve?["Web"] as? [String: Any],
              let entry = web[key] as? [String: Any],
              let handlers = entry["Handlers"] as? [String: Any],
              let root = handlers["/"] as? [String: Any],
              let proxy = root["Proxy"] as? String else {
            return .notServing(host: host)
        }
        let targets = ["http://127.0.0.1:\(aeriePort)", "http://localhost:\(aeriePort)", "\(aeriePort)"]
        if targets.contains(where: { proxy == $0 || proxy == $0 + "/" }) {
            return .serving(url: URL(string: "https://\(key)/")!)
        }
        return .conflict(host: host, target: proxy)
    }

    nonisolated private static func run(_ path: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}

/// The Mac-side gate on pairing: a modal Allow/Deny alert, Deny by default,
/// gone after 60 s. One at a time — a second request while one is showing is
/// refused rather than queued, so a stranger can't stack dialogs.
@MainActor
enum MobilePairApproval {
    private static var showing = false

    /// true = Allow, false = Deny, nil = no answer in time.
    static func ask(deviceName: String, client: String) async -> Bool? {
        guard !showing else { return false }
        showing = true
        defer { showing = false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow “\(deviceName)” to use Aerie?"
        alert.informativeText = """
            A phone is asking to pair from \(client).

            Once paired it can see your pull requests and approve or merge them \
            as your GitHub accounts. Only allow it if this is your own phone \
            and you just tapped “Link this iPhone”.
            """
        alert.addButton(withTitle: "Deny")
        alert.addButton(withTitle: "Allow")

        var timedOut = false
        let timer = Timer(timeInterval: 60, repeats: false) { _ in
            timedOut = true
            NSApp.abortModal()
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        let response = alert.runModal()
        timer.invalidate()
        if timedOut { return nil }
        return response == .alertSecondButtonReturn
    }
}
