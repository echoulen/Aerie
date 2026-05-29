import AppKit
import Combine
import SwiftUI

@main
struct AerieApp: App {
    @NSApplicationDelegateAdaptor(AerieAppDelegate.self) private var appDelegate

    private let services = AppServices.shared

    @State private var bootstrapper: GhBootstrapper = {
        GhBootstrapper(auth: AppServices.shared.auth, interval: 5.0)
    }()

    var body: some Scene {
        WindowGroup("Aerie") {
            AppRoot(bootstrapper: bootstrapper, onAuthOK: startMCPServer)
                .frame(minWidth: 1240, minHeight: 880)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }

        Window("Aerie · Settings", id: "settings") {
            SettingsWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    /// Called by ``AppRoot`` exactly once when the auth state first transitions
    /// to `.ok`. Starts the MCP server, hands it to the app delegate so
    /// `applicationWillTerminate` can stop it, and writes the discovery file.
    private func startMCPServer() {
        let server = services.mcpServer
        let discovery = services.discovery
        let delegate = appDelegate
        Task {
            do {
                try await server.start()
                guard let endpoint = await server.endpoint,
                      let token = await server.token
                else {
                    NSLog("MCP server started but endpoint/token unavailable")
                    return
                }
                // Hand-off to the @MainActor delegate must happen on the main
                // actor — we use MainActor.run rather than a method `await`
                // because attach() is a synchronous setter and Swift won't
                // insert the actor hop otherwise.
                await MainActor.run {
                    delegate.attach(server: server, discovery: discovery)
                }
                try discovery.write(endpoint: endpoint.absoluteString, token: token)
                // TODO(Phase 20): also write ~/.claude/.mcp.json (with consent UI).
            } catch {
                // Phase 20 will surface this in the MCP settings card. For now
                // log it — the rest of the app still works without MCP.
                NSLog("MCP start failed: \(error)")
            }
        }
    }
}

private struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Settings…") {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

/// Branches between the first-run flow and the main shell based on the
/// bootstrapper's current ``AuthBootstrapResult``. Calls ``onAuthOK`` exactly
/// once when state first transitions to `.ok` — used to kick off the MCP
/// server lifecycle from ``AerieApp``.
private struct AppRoot: View {
    let bootstrapper: GhBootstrapper
    var onAuthOK: () -> Void = {}

    @State private var current: AuthBootstrapResult? = nil
    @State private var sub: AnyCancellable? = nil
    @State private var didFireOnAuthOK = false

    var body: some View {
        Group {
            switch current {
            case .ok:
                MainShell()
            case .ghMissing, .noAuth:
                FirstRunRoot(bootstrapper: bootstrapper)
            case .none:
                // Bootstrapper hasn't completed its first call yet. Show a
                // bare Backdrop so users with gh already configured don't see
                // a one-frame flash of "Install GitHub CLI" before MainShell
                // appears.
                ZStack { Backdrop() }
                    .frame(minWidth: AerieMetric.mainWindowW, minHeight: AerieMetric.mainWindowH)
                    .aerieWindowChrome()
            }
        }
        .onAppear {
            sub = bootstrapper.state.sink { value in
                current = value
                if case .ok = value, !didFireOnAuthOK {
                    didFireOnAuthOK = true
                    onAuthOK()
                }
            }
            bootstrapper.start()
        }
    }
}

/// The composed main window shell — Backdrop + Titlebar (centred brand) + the
/// currently-selected primary screen (PRs or Repos). The view switcher lives
/// in the active screen's page header.
///
/// View models are constructed once per shell, seeded with the shared
/// `AppServices.shared.db`, and refreshed on first appear. Polling-driven
/// auto-refresh and the toast overlay are tracked as Known Issues in the plan.
struct MainShell: View {
    private let services = AppServices.shared
    @Environment(\.openWindow) private var openWindow
    @State private var appVM = AppViewModel()
    @State private var prsVM: PRsViewModel
    @State private var reposVM: ReposViewModel
    @State private var accountVM: AccountMenuViewModel

    init() {
        let db = AppServices.shared.db
        _prsVM = State(initialValue: PRsViewModel(db: db))
        _reposVM = State(initialValue: ReposViewModel(db: db))
        let auth = AppServices.shared.auth
        _accountVM = State(initialValue: AccountMenuViewModel(
            accounts: { await auth.allAccounts() },
            primaryId: { await auth.primaryAccountId() }
        ))
    }

    var body: some View {
        AppFrame(
            viewModel: appVM,
            accountMenu: accountVM,
            onOpenSettings: { openWindow(id: "settings") }
        ) {
            Group {
                switch appVM.activeTab {
                case .prs:   PRsScreen(viewModel: prsVM, tabSelection: $appVM.activeTab)
                case .repos: ReposScreen(viewModel: reposVM, tabSelection: $appVM.activeTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await prsVM.refresh()
            await reposVM.refresh()
            await accountVM.refresh()
        }
    }
}

// MARK: - App delegate

/// Hooks NSApplication lifecycle so we can stop the MCP server and clear the
/// discovery file before the process exits.
///
/// Marked `final class` + `@MainActor` because `NSApplicationDelegateAdaptor`
/// requires the delegate to be on the main actor. The MCP server is an actor,
/// so we hop off via a Task and wait with a bounded `DispatchSemaphore` —
/// `applicationWillTerminate` is synchronous and we mustn't block AppKit
/// indefinitely.
@MainActor
final class AerieAppDelegate: NSObject, NSApplicationDelegate {
    private var mcpServer: MCPServer?
    private var discovery: DiscoveryFileWriter?

    func attach(server: MCPServer, discovery: DiscoveryFileWriter) {
        self.mcpServer = server
        self.discovery = discovery
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        // Snapshot the server/discovery on the main actor, then do the
        // shutdown work asynchronously with a bounded wait.
        let sema = DispatchSemaphore(value: 0)
        Task { @MainActor in
            let server = self.mcpServer
            let discovery = self.discovery
            // Don't hold the main actor while stopping — let stop() drive
            // the actor hop itself.
            Task.detached {
                if let server { await server.stop() }
                if let discovery { try? discovery.clear() }
                sema.signal()
            }
        }
        // Cap the wait so a hung shutdown doesn't keep AppKit from exiting.
        _ = sema.wait(timeout: .now() + 2.0)
    }
}
