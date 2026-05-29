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

        _accountsVM = State(initialValue: AccountsViewModel(
            db: db,
            api: multiApi,
            scopesByAccount: { [:] },
            primaryAccountId: { nil }
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
            }
            if showAddRepo {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { showAddRepo = false }
                AddRepoSheet(
                    viewModel: addRepoVM,
                    onCancel: { showAddRepo = false },
                    onAdd: { _ in
                        showAddRepo = false
                        Task { await reposVM.refresh() }
                    }
                )
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
            AccountsScreen(viewModel: accountsVM)
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
