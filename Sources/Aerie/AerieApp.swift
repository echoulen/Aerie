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
        // Snapshot the services the wiring needs — the Task below is @Sendable
        // and must not capture the @MainActor `services`/`self`.
        let registry = services.mcpRegistry
        let router = services.mcpRouter
        let db = services.db
        let git = services.gitService
        let api = services.multiApi
        let scheduler = services.scheduler
        let auth = services.auth
        let configWriter = services.configWriter
        Task {
            do {
                // Wire the MCP protocol methods + tool roster BEFORE the listener
                // accepts requests — without handlers, every call (including the
                // `initialize` handshake) is -32601 and clients can't connect.
                await MCPToolset.registerAll(
                    into: registry,
                    db: db,
                    git: git,
                    api: api,
                    accounts: { await auth.allAccounts() },
                    refresh: { repoId in
                        await scheduler.refreshNow(repoIds: [repoId], now: Date())
                    },
                    accountToken: { accountId in await auth.token(for: accountId) }
                )
                let appVersion = Bundle.main
                    .infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                await MCPMethods.install(
                    on: router,
                    registry: registry,
                    serverInfo: .init(name: "Aerie", version: appVersion)
                )

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
                // Keep Claude Code's ~/.claude.json entry pointed at THIS launch's
                // endpoint/token when auto-register is on (both are fresh each
                // launch). The writer's no-op guard makes a repeat call cheap.
                let autoOn = (try? await db.settings.getBool("mcp.auto_register_claude_code")) ?? nil
                if autoOn == true {
                    try? configWriter.upsertAerie(
                        endpoint: endpoint.absoluteString, token: token
                    )
                }
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

/// Pairs a worktree with its repo for the worktree dialogs' `@State`.
struct WorktreeContext: Identifiable, Equatable {
    let id: String           // worktree path — unique per repo
    let repo: Repository
    let worktree: WorktreeRow
    init(repo: Repository, worktree: WorktreeRow) {
        self.id = worktree.id
        self.repo = repo
        self.worktree = worktree
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
    @State private var aiReviewStore: AIReviewStore = MainShell.makeAIReviewStore()
    @Environment(\.openWindow) private var openWindow
    @State private var appVM = AppViewModel()
    @State private var prsVM: PRsViewModel
    @State private var issuesVM: IssuesViewModel
    @State private var reposVM: ReposViewModel
    @State private var accountVM: AccountMenuViewModel
    /// The repo whose hard-reset confirmation dialog is currently presented
    /// (nil = no dialog). Owned here so the `DialogReset` scrim dims the whole
    /// window, not just the Repos content area.
    @State private var presentedReset: RepoRow?
    /// The repo whose discard-unstaged confirmation dialog is currently presented
    /// (nil = no dialog). Owned here for the same scrim reason as `presentedReset`.
    @State private var presentedDiscard: RepoRow?
    /// The PR whose merge confirmation dialog is currently presented (nil = no
    /// dialog). Owned here for the same reason as `presentedReset` — the
    /// `DialogMerge` scrim should dim the whole window.
    @State private var presentedMerge: PRRow?
    /// The PR whose force-checkout confirmation dialog is currently presented
    /// (nil = no dialog). Owned here for the same scrim reason as the others.
    @State private var presentedCheckout: PRRow?
    /// The PR currently open in the code review (diff) screen, or nil for the
    /// normal tab list. Owned here (not in `AppViewModel`) alongside the dialogs,
    /// since the review screen replaces the whole tab content area.
    @State private var reviewing: PRRow?
    /// The PR + resolved approver set for the approve confirmation dialog
    /// (nil = no dialog). Owned here for the same scrim reason as the others.
    @State private var presentedApprove: PRReviewApproveContext?
    /// The (repo, worktree) whose delete confirmation is presented (nil = none).
    @State private var presentedDeleteWorktree: WorktreeContext?
    /// The (repo, worktree) whose discard confirmation is presented (nil = none).
    @State private var presentedDiscardWorktree: WorktreeContext?
    /// GitHub accounts indexed by id, loaded once on appear so the merge dialog
    /// can resolve a PR's bound account (`repo.primaryAccountId`) synchronously
    /// for display. The overlay body can't `await`, hence the cached map.
    @State private var accountsById: [UUID: GitHubAccount] = [:]

    init() {
        let db = AppServices.shared.db
        _prsVM = State(initialValue: PRsViewModel(db: db))
        _issuesVM = State(initialValue: IssuesViewModel(db: db))
        _reposVM = State(initialValue: ReposViewModel(
            db: db, gitService: AppServices.shared.gitService))
        let auth = AppServices.shared.auth
        _accountVM = State(initialValue: AccountMenuViewModel(
            accounts: { await auth.allAccounts() },
            primaryId: { await auth.primaryAccountId() }
        ))
    }

    // The active tab's screen. Extracted from `body` so the SwiftUI view-builder
    // type-checker solves a smaller expression — the full `body` with all three
    // dialog overlays otherwise exceeds the "unable to type-check in reasonable
    // time" limit.
    @ViewBuilder
    private var tabContent: some View {
        if let row = reviewing {
            // Code review (diff) screen replaces the tab list while open. Keyed
            // on the PR id so switching PRs rebuilds the screen + its fetch.
            PRReviewScreen(
                row: row,
                store: aiReviewStore,
                loadFiles: { r in
                    try await services.multiApi.fetchPRFiles(
                        owner: r.repo.githubOwner,
                        repo: r.repo.githubRepo,
                        number: r.pr.number,
                        accountId: r.repo.primaryAccountId
                    ).value
                },
                accountsProvider: { await services.auth.allAccounts() },
                onBack: { reviewing = nil },
                onApprove: { presentedApprove = $0 }
            )
            .id(row.id)
        } else {
            tabSwitcher
        }
    }

    @ViewBuilder
    private var tabSwitcher: some View {
        switch appVM.activeTab {
        case .prs:
            PRsScreen(
                viewModel: prsVM,
                tabSelection: $appVM.activeTab,
                onRefresh: { await services.refreshNow() },
                onMerge: { presentedMerge = $0 },
                onUpdateBranch: { row in
                    // One-click "Update branch": ask GitHub to update the PR's
                    // head branch server-side (the analogue of the web "Update
                    // branch" button), then re-sync so the row's BEHIND state
                    // (and the pill) clear. No dialog: a forward, non-destructive
                    // step.
                    //
                    // Always the server path — even when the branch is the local
                    // checkout. A local `git merge` advances only the working
                    // copy; without a push the PR's *remote* head never moves, so
                    // GitHub keeps reporting BEHIND and the merge stays blocked
                    // (PR #807: the local merge had already happened but never
                    // reached GitHub). The server update moves the remote head,
                    // which is what BEHIND is computed against. The bound
                    // account's token is resolved inside MultiAccountAPI.
                    do {
                        try await services.multiApi.updatePullRequestBranch(
                            owner: row.repo.githubOwner,
                            repo: row.repo.githubRepo,
                            number: row.pr.number
                        )
                    } catch {
                        NSLog("Update branch failed for \(row.repo.name) #\(row.pr.number): \(error.localizedDescription)")
                    }
                    await services.refreshNow()
                },
                onCheckout: { presentedCheckout = $0 },
                onReview: { reviewing = $0 }
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
                },
                onHardReset: { presentedReset = $0 },
                onDiscard: { presentedDiscard = $0 },
                onMergeWorktree: { row, wt in
                    // No dialog: a forward, non-destructive step. Mirrors the
                    // PR card's onUpdateBranch — merge origin/<default> into the
                    // worktree, authenticated as the repo's bound account, then
                    // re-project so the row's dirty/clean state settles. Returns
                    // nil on success / an error string on failure so the Merge
                    // button can drive its idle → Merging… → Up to date loop.
                    do {
                        let token = await services.auth.token(
                            for: row.repo.primaryAccountId)
                        try await services.gitService.updateBranchFromBase(
                            repoAt: wt.path,
                            defaultBranch: row.repo.defaultBranch,
                            token: token)
                        await reposVM.refresh()
                        return nil
                    } catch {
                        NSLog("Worktree merge failed for \(row.repo.name) @ \(wt.branchLabel): \(error.localizedDescription)")
                        return error.localizedDescription
                    }
                },
                onDiscardWorktree: { row, wt in
                    presentedDiscardWorktree = WorktreeContext(repo: row.repo, worktree: wt)
                },
                onDeleteWorktree: { row, wt in
                    presentedDeleteWorktree = WorktreeContext(repo: row.repo, worktree: wt)
                }
            )
        }
    }

    // Hard-reset confirmation overlay content. Extracted (like the other dialogs)
    // to keep `body` within the type-checker's complexity budget.
    @ViewBuilder
    private var resetDialog: some View {
        if let row = presentedReset, let status = row.status {
            DialogReset(
                repo: row.repo,
                status: status,
                mergedBranch: row.mergedBranch,
                onConfirm: {
                    do {
                        let token = await services.auth.token(
                            for: row.repo.primaryAccountId
                        )
                        _ = try await services.gitService.hardResetToOrigin(
                            repoAt: row.repo.localPath,
                            defaultBranch: row.repo.defaultBranch,
                            token: token
                        )
                        // Reset succeeded — HEAD is now on the default branch, so the
                        // merged branch can be force-deleted. A deletion failure here is
                        // non-fatal: the reset already achieved the user's goal and the
                        // orphaned merged branch is harmless (removable manually). Swallow
                        // + log rather than reporting "Reset failed", which would
                        // misrepresent a successful reset. refreshNow re-runs detection;
                        // since HEAD is now on default, the pill clears regardless.
                        if let merged = row.mergedBranch {
                            do {
                                try await services.gitService.deleteLocalBranch(
                                    repoAt: row.repo.localPath,
                                    branch: merged.branch
                                )
                            } catch {
                                NSLog("Reset succeeded but couldn't delete merged branch \(merged.branch): \(error.localizedDescription)")
                            }
                        }
                        await services.refreshNow()
                        presentedReset = nil
                        return nil
                    } catch {
                        return "Reset failed: \(error.localizedDescription)"
                    }
                },
                onCancel: { presentedReset = nil }
            )
        }
    }

    // Discard-unstaged confirmation overlay content. Confirm runs `git restore .`
    // off the bound git service, then refreshes so the card moves toward
    // "Clean · in sync" and the Discard button (and this dialog) drop out.
    @ViewBuilder
    private var discardDialog: some View {
        if let row = presentedDiscard, let status = row.status {
            DialogDiscard(
                repo: row.repo,
                status: status,
                onConfirm: {
                    do {
                        try await services.gitService.discardUnstaged(
                            repoAt: row.repo.localPath
                        )
                        await services.refreshNow()
                        presentedDiscard = nil
                        return nil
                    } catch {
                        return "Discard failed: \(error.localizedDescription)"
                    }
                },
                onCancel: { presentedDiscard = nil }
            )
        }
    }

    // Merge confirmation overlay content. Confirm squash-merges via the GitHub
    // API, then refreshes so the merged PR drops off the list.
    @ViewBuilder
    private var mergeDialog: some View {
        if let row = presentedMerge {
            DialogMerge(
                pr: row.pr,
                repo: row.repo,
                account: accountsById[row.repo.primaryAccountId]
                    ?? GitHubAccount(id: row.repo.primaryAccountId, login: "unknown", host: "github.com"),
                onConfirm: {
                    do {
                        _ = try await services.multiApi.mergePR(
                            owner: row.repo.githubOwner,
                            repo: row.repo.githubRepo,
                            number: row.pr.number,
                            method: .squash
                        )
                        await services.refreshNow()
                        presentedMerge = nil
                        return nil
                    } catch {
                        return "Merge failed: \(error.localizedDescription)"
                    }
                },
                onCancel: { presentedMerge = nil }
            )
        }
    }

    // Force-checkout confirmation overlay content. Confirm runs the bound git
    // service's `forceCheckout`, then refreshes so the PR's local-state pill
    // settles to "clean & in sync" (the branch is now checked out at origin).
    @ViewBuilder
    private var checkoutDialog: some View {
        if let row = presentedCheckout {
            DialogCheckout(
                repo: row.repo,
                pr: row.pr,
                local: row.localState,
                onConfirm: {
                    do {
                        let token = await services.auth.token(
                            for: row.repo.primaryAccountId
                        )
                        try await services.gitService.forceCheckout(
                            repoAt: row.repo.localPath,
                            branch: row.pr.sourceBranch,
                            token: token
                        )
                        await services.refreshNow()
                        presentedCheckout = nil
                        return nil
                    } catch {
                        return "Checkout failed: \(error.localizedDescription)"
                    }
                },
                onCancel: { presentedCheckout = nil }
            )
        }
    }

    // Approve confirmation overlay content. Confirm submits an approving review
    // via the GitHub API using the chosen (non-author) approver account, then
    // refreshes so the PR's review state — and the Merge gate — settle.
    @ViewBuilder
    private var approveDialog: some View {
        if let ctx = presentedApprove {
            DialogApprove(
                context: ctx,
                onConfirm: { approver, comment in
                    do {
                        _ = try await services.multiApi.approvePR(
                            owner: ctx.row.repo.githubOwner,
                            repo: ctx.row.repo.githubRepo,
                            number: ctx.row.pr.number,
                            body: comment,
                            accountId: approver.id
                        )
                        await services.refreshNow()
                        presentedApprove = nil
                        // Approve done → leave the diff detail page and return to
                        // the PR list, where the row now reflects the new review
                        // state (and any lit Merge gate).
                        reviewing = nil
                        return nil
                    } catch {
                        return "Approve failed: \(error.localizedDescription)"
                    }
                },
                onCancel: { presentedApprove = nil }
            )
        }
    }

    /// Builds the AI-review store, wiring its closures to live services. Static so
    /// it can seed the `@State` initial value without touching `self`.
    @MainActor
    private static func makeAIReviewStore() -> AIReviewStore {
        let services = AppServices.shared
        let claude: ClaudeReviewService = LiveClaudeReviewService()
        return AIReviewStore(
            loadFiles: { r in
                try await services.multiApi.fetchPRFiles(
                    owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                    number: r.pr.number, accountId: r.repo.primaryAccountId).value
            },
            runReview: { r, diff, onLine in
                await claude.review(
                    owner: r.repo.githubOwner, repo: r.repo.githubRepo, number: r.pr.number,
                    title: r.pr.title, author: r.pr.authorLogin, sourceBranch: r.pr.sourceBranch,
                    diff: diff, localPath: r.repo.localPath, onLine: onLine)
            },
            resolveApprover: { r in
                let accounts = await services.auth.allAccounts()
                return ApproverResolver.resolve(
                    accounts: accounts, boundAccountId: r.repo.primaryAccountId,
                    authorLogin: r.pr.authorLogin)
            },
            approve: { r, approver, body in
                do {
                    _ = try await services.multiApi.approvePR(
                        owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                        number: r.pr.number, body: body, accountId: approver.id)
                    await services.refreshNow()
                    return nil
                } catch { return error.localizedDescription }
            },
            comment: { r, approver, body in
                do {
                    _ = try await services.multiApi.addIssueComment(
                        owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                        number: r.pr.number, body: body, accountId: approver.id)
                    await services.refreshNow()
                    return nil
                } catch { return error.localizedDescription }
            })
    }

    // Delete-worktree confirmation overlay content. Confirm runs `git worktree
    // remove` off the bound git service (force when the worktree is dirty), then
    // refreshes the ReposViewModel so the worktree rail updates immediately.
    // Worktrees are recomputed by the VM (not the DB/polling layer), so we call
    // `reposVM.refresh()` rather than `services.refreshNow()`.
    @ViewBuilder
    private var deleteWorktreeDialog: some View {
        if let ctx = presentedDeleteWorktree {
            DialogDeleteWorktree(
                repo: ctx.repo,
                worktree: ctx.worktree,
                onConfirm: {
                    do {
                        try await services.gitService.removeWorktree(
                            ctx.worktree.path,
                            mainWorktreeAt: ctx.repo.localPath,
                            force: ctx.worktree.isDirty)
                        await reposVM.refresh()
                        presentedDeleteWorktree = nil
                        return nil
                    } catch {
                        return "Delete failed: \(error.localizedDescription)"
                    }
                },
                onCancel: { presentedDeleteWorktree = nil })
        }
    }

    // Discard-worktree confirmation overlay content. Confirm runs `git restore .`
    // + `git clean -fd` off the bound git service, then refreshes the
    // ReposViewModel so the worktree rail updates immediately.
    @ViewBuilder
    private var discardWorktreeDialog: some View {
        if let ctx = presentedDiscardWorktree {
            DialogWorktreeDiscard(
                repo: ctx.repo,
                worktree: ctx.worktree,
                onConfirm: {
                    do {
                        try await services.gitService.discardUnstaged(
                            repoAt: ctx.worktree.path)
                        await reposVM.refresh()
                        presentedDiscardWorktree = nil
                        return nil
                    } catch {
                        return "Discard failed: \(error.localizedDescription)"
                    }
                },
                onCancel: { presentedDiscardWorktree = nil })
        }
    }

    var body: some View {
        AppFrame(
            viewModel: appVM,
            accountMenu: accountVM,
            onOpenSettings: { openWindow(id: "settings") }
        ) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Confirmation dialogs — each carries its own full-window scrim (via
        // `DialogShell`), so overlaying here dims the titlebar too. Content is
        // extracted into computed properties to keep `body` type-checkable.
        .overlay { resetDialog }
        .overlay { discardDialog }
        .overlay { mergeDialog }
        .overlay { checkoutDialog }
        .overlay { approveDialog }
        .overlay { deleteWorktreeDialog }
        .overlay { discardWorktreeDialog }
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
            // Cache accounts by id so the merge dialog can show a PR's bound
            // account without an await in the (synchronous) overlay body.
            accountsById = Dictionary(
                (await services.auth.allAccounts()).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
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
