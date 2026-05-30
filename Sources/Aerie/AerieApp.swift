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

    /// Single shared interface-zoom state. Both windows read its
    /// `dynamicTypeSize`, and the Settings → Appearance screen mutates the same
    /// instance, so adjusting the control rescales the whole app live.
    @State private var appearance = AppearanceViewModel(db: AppServices.shared.db)

    var body: some Scene {
        WindowGroup("Aerie") {
            InterfaceZoom(appearance: appearance) {
                AppRoot(bootstrapper: bootstrapper, onAuthOK: startMCPServer)
                    .frame(minWidth: 1240, minHeight: 880)
            }
            .task { await appearance.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }

        Window("Aerie · Settings", id: "settings") {
            InterfaceZoom(appearance: appearance) {
                SettingsWindow(appearance: appearance)
            }
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

/// Publishes the shared interface font scale into the environment as
/// `\.interfaceFontScale`. Text uses `.aerieFont(_:)` (which reads that value),
/// so changing the Appearance control rescales every font app-wide — crisply
/// (real font sizes, no rasterisation) and with no state loss. Reading
/// `appearance.scale` here sets up `@Observable` tracking so the value updates
/// the instant the selection changes.
private struct InterfaceZoom<Content: View>: View {
    let appearance: AppearanceViewModel
    @ViewBuilder var content: Content

    var body: some View {
        content.environment(\.interfaceFontScale, appearance.scale)
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
    @State private var issuesVM: IssuesViewModel
    @State private var reposVM: ReposViewModel
    @State private var accountVM: AccountMenuViewModel

    init() {
        let db = AppServices.shared.db
        _prsVM = State(initialValue: PRsViewModel(db: db))
        _issuesVM = State(initialValue: IssuesViewModel(db: db))
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
                case .prs:
                    PRsScreen(
                        viewModel: prsVM,
                        tabSelection: $appVM.activeTab,
                        onRefresh: { await services.refreshNow() }
                    )
                case .issues:
                    IssuesScreen(
                        viewModel: issuesVM,
                        tabSelection: $appVM.activeTab,
                        onRefresh: { await services.refreshNow() }
                    )
                case .repos:
                    ReposScreen(
                        viewModel: reposVM,
                        tabSelection: $appVM.activeTab,
                        onRefresh: { await services.refreshNow() },
                        onAddRepo: {
                            services.settingsNavigator.requestAddRepo()
                            openWindow(id: "settings")
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            // Kick off focus-driven polling (idempotent), then paint instantly
            // from whatever's already cached. Fresh PRs arrive via the
            // `.aeriePRCacheDidChange` notification, and fresh git status via
            // `gitStatusDidChange`, once the first tick syncs. The view is
            // already mounted here, so both .onReceive subscriptions below are
            // attached before the first tick can emit.
            services.startPolling()
            await prsVM.refresh()
            await issuesVM.refresh()
            await reposVM.refresh()
            await accountVM.refresh()
        }
        // Re-read repo cards whenever a polling tick upserts fresh status.
        // Throttled so N repos in one tick don't trigger N full re-reads.
        .onReceive(
            services.gitStatusDidChange
                .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
        ) { _ in
            Task { await reposVM.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aeriePRCacheDidChange)) { _ in
            Task { await prsVM.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aerieIssueCacheDidChange)) { _ in
            Task { await issuesVM.refresh() }
        }
        // A repo was added/removed in Settings. Re-project all three tabs so the
        // change shows immediately, then kick a real sync so the new repo's git
        // status / PRs / issues populate without waiting for the next tick.
        .onReceive(NotificationCenter.default.publisher(for: .aerieReposDidChange)) { _ in
            Task {
                await reposVM.refresh()
                await prsVM.refresh()
                await issuesVM.refresh()
                await services.refreshNow()
            }
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
