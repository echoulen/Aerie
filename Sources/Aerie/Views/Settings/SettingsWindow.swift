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
    @State private var appearanceVM: AppearanceViewModel
    @State private var mcpVM: MCPSettingsViewModel
    @State private var showAddRepo: Bool = false
    @State private var addRepoVM = AddRepoSheetViewModel()
    /// The account whose "Sign out…" confirmation dialog is showing, plus the
    /// repos that use it as primary (computed when the dialog opens so the
    /// dialog can spell out the blast radius). Nil when no dialog is up.
    @State private var signOutTarget: AccountRow? = nil
    @State private var signOutAffectedRepos: [Repository] = []

    /// `appearance` is the app-wide shared zoom state, injected by `AerieApp`
    /// so the Settings control and the main window stay in sync. Defaults to a
    /// fresh instance when omitted (previews / snapshot tests).
    init(appearance: AppearanceViewModel? = nil) {
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
        _appearanceVM = State(initialValue: appearance ?? AppearanceViewModel(db: db))
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
                            onAdd: { detected in
                                showAddRepo = false
                                Task { await reposVM.add(detected) }
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
        // Pull the titlebar up under the native traffic lights — same top
        // safe-area inset fix as AppFrame, so "Aerie · Settings" lines up with
        // the window controls instead of sitting a title-bar height too low.
        .ignoresSafeArea(.container, edges: .top)
        // Sign-out confirmation. DialogShell brings its own full-window scrim
        // (and ignoresSafeArea), so it overlays the whole window — no extra
        // scrim/blur needed here, unlike the AddRepo sheet above.
        .overlay {
            if let target = signOutTarget {
                DialogSignOut(
                    account: target.account,
                    affectedRepos: signOutAffectedRepos,
                    onConfirm: {
                        try? await services.auth.signOut(accountId: target.account.id)
                        _ = try? await services.auth.bootstrap()
                        await accountsVM.refresh()
                        signOutTarget = nil
                    },
                    onCancel: { signOutTarget = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: signOutTarget)
        .frame(minWidth: AerieMetric.settingsWindowW, minHeight: AerieMetric.settingsWindowH)
        .aerieWindowChrome()
        .task(id: route.wrappedValue) {
            await refreshActive(route: route.wrappedValue)
        }
        // Honour a deep-link from the main window's "Add repository" button.
        // `onAppear` covers a freshly-opened Settings window; `onChange` covers
        // the case where Settings is already open and merely refocused.
        .onAppear { consumeNavigationIntent() }
        .onChange(of: services.settingsNavigator.pendingAddRepo) { _, newValue in
            if newValue { consumeNavigationIntent() }
        }
    }

    /// Reads (and clears) any pending cross-window navigation request: jumps to
    /// the requested route and, if asked, opens the add-repo sheet once its repo
    /// list + accounts have loaded.
    private func consumeNavigationIntent() {
        let pending = services.settingsNavigator.consume()
        if let r = pending.route { routeRaw = r.rawValue }
        guard pending.showAddRepo else { return }
        Task {
            await reposVM.refresh()
            addRepoVM.reset()
            addRepoVM.accounts = reposVM.accounts
            showAddRepo = true
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
                },
                onMakePrimary: { row in
                    Task {
                        try? await services.auth.makePrimary(accountId: row.account.id)
                        // Re-bootstrap so primaryAccountId() reflects the switch.
                        _ = try? await services.auth.bootstrap()
                        await accountsVM.refresh()
                    }
                },
                onSignOut: { row in
                    Task {
                        let repos = (try? await services.db.repos.all()) ?? []
                        signOutAffectedRepos = repos.filter { $0.primaryAccountId == row.account.id }
                        signOutTarget = row
                    }
                }
            )
        case .repositories:
            RepositoriesScreen(
                viewModel: reposVM,
                onRefreshAll: { Task { await reposVM.refresh() } },
                onAddRepo: {
                    addRepoVM.reset()
                    // Feed the loaded accounts in so RepoDetector can match a
                    // primary account by host (otherwise suggestion is always nil).
                    addRepoVM.accounts = reposVM.accounts
                    showAddRepo = true
                }
            )
        case .mcp:
            MCPSettingsScreen(viewModel: mcpVM)
        case .appearance:
            AppearanceScreen(viewModel: appearanceVM)
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
        case .appearance:   await appearanceVM.refresh()
        case .advanced:     await advancedVM.refresh()
        case .about:        break
        }
    }
}
