import SwiftUI

struct SettingsWindow: View {
    private let services = AppServices.shared

    @SceneStorage("settings.route") private var routeRaw: String = SettingsRoute.accounts.rawValue
    private var route: Binding<SettingsRoute> {
        Binding(
            get: { SettingsRoute(rawValue: routeRaw) ?? .accounts },
            set: { routeRaw = $0.rawValue }
        )
    }

    @State private var accountsVM: AccountsViewModel
    @State private var reposVM: RepositoriesViewModel
    @State private var advancedVM: AdvancedViewModel
    @State private var mcpVM: MCPSettingsViewModel
    @State private var showAddRepo: Bool = false
    @State private var addRepoVM = AddRepoSheetViewModel()

    init() {
        let svc = AppServices.shared
        let db = svc.db
        let multiApi = svc.multiApi
        let server = svc.mcpServer
        let configWriter = svc.configWriter
        let scheduler = svc.scheduler

        let auth = svc.auth
        _accountsVM = State(initialValue: AccountsViewModel(
            db: db,
            api: multiApi,
            scopesByAccount: { await auth.scopesByAccount() },
            primaryAccountId: { await auth.primaryAccountId() },
            ghVersion: { await auth.ghVersion() }
        ))
        _reposVM = State(initialValue: RepositoriesViewModel(db: db))
        _advancedVM = State(initialValue: AdvancedViewModel(
            db: db,
            cadenceApplier: { active, background in
                await scheduler.setCadences(active: active, background: background)
            },
            rateLimitProvider: { accountId in
                await multiApi.rateLimit(forAccount: accountId)
            }
        ))
        _mcpVM = State(initialValue: MCPSettingsViewModel(
            db: db,
            serverStatus: {
                let running = await server.token != nil
                let endpoint = await server.endpoint
                return .init(
                    running: running,
                    pid: Int(ProcessInfo.processInfo.processIdentifier),
                    uptimeSeconds: nil,
                    endpoint: endpoint
                )
            },
            tokenProvider: { (await server.token) ?? "" },
            rotateToken: { _ = await server.rotateToken() },
            runConfigUpsert: {
                guard let endpoint = await server.endpoint,
                      let token = await server.token else { return }
                try? configWriter.upsertAerie(endpoint: endpoint.absoluteString, token: token)
            },
            runConfigRemove: { try? configWriter.removeAerie() }
        ))
    }

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                Titlebar(title: "Aerie · Settings")
                // Inner ZStack so the scrim and sheet are constrained to the
                // area BELOW the titlebar. Per `add-repo.jsx`, the AddRepo
                // sheet slides down from the titlebar — that requires the
                // scrim to start at the bottom of the title bar (not over it).
                ZStack(alignment: .top) {
                    HStack(spacing: 0) {
                        SettingsSidebar(
                            selection: route,
                            mcpRunning: mcpVM.status.running,
                            accountsCount: accountsVM.rows.count,
                            repositoriesCount: reposVM.repos.count
                        )
                        body(for: route.wrappedValue)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Mirror `add-repo.jsx`: blur + desat + opacity on the
                    // parent so the sheet visibly floats above it.
                    .blur(radius: showAddRepo ? 2 : 0)
                    .saturation(showAddRepo ? 0.85 : 1)
                    .opacity(showAddRepo ? 0.55 : 1)
                    .allowsHitTesting(!showAddRepo)
                    .animation(.easeOut(duration: 0.15), value: showAddRepo)

                    if showAddRepo {
                        // Dark scrim, scoped to the content area (titlebar
                        // stays clear). 0.30 matches the design.
                        Color.black.opacity(0.30)
                            .onTapGesture { showAddRepo = false }
                        AddRepoSheet(
                            viewModel: addRepoVM,
                            onCancel: { showAddRepo = false },
                            onAdd: { _ in
                                showAddRepo = false
                                Task { await reposVM.refresh() }
                            }
                        )
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: showAddRepo)
            }
        }
        .frame(minWidth: AerieMetric.settingsWindowW, minHeight: AerieMetric.settingsWindowH)
        .aerieWindowChrome()
        .task(id: route.wrappedValue) {
            await refreshActive(route: route.wrappedValue)
        }
    }

    @ViewBuilder
    private func body(for route: SettingsRoute) -> some View {
        switch route {
        case .accounts:
            AccountsScreen(
                viewModel: accountsVM,
                ghVersion: accountsVM.ghVersion ?? "gh version unknown",
                onRescan: {
                    _ = try? await services.auth.bootstrap()
                    await accountsVM.refresh()
                }
            )
        case .repositories:
            RepositoriesScreen(
                viewModel: reposVM,
                onRefreshAll: { Task { await reposVM.refresh() } },
                onAddRepo: {
                    addRepoVM.reset()
                    showAddRepo = true
                }
            )
        case .mcp:
            MCPSettingsScreen(viewModel: mcpVM)
        case .advanced:
            AdvancedScreen(viewModel: advancedVM)
        case .about:
            AboutScreen()
        }
    }

    private func refreshActive(route: SettingsRoute) async {
        switch route {
        case .accounts:     await accountsVM.refresh()
        case .repositories: await reposVM.refresh()
        case .mcp:          await mcpVM.refresh()
        case .advanced:     await advancedVM.refresh()
        case .about:        break
        }
    }
}
