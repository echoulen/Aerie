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
                AppRoot(bootstrapper: bootstrapper)
                    .frame(minWidth: AerieMetric.mainWindowW, minHeight: AerieMetric.mainWindowH)
            }
            .task { await appearance.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                UpdateCommand()
            }
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

}

private struct UpdateCommand: View {
    var body: some View {
        Button("Check for Updates…") {
            UpdatePresenter.checkAndPresent(store: AppServices.shared.updates)
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
/// bootstrapper's current ``AuthBootstrapResult``.
private struct AppRoot: View {
    let bootstrapper: GhBootstrapper

    @State private var current: AuthBootstrapResult? = nil
    @State private var sub: AnyCancellable? = nil

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
    @State private var aiReviewStore: AIReviewStore = MainShell.makeAIReviewStore()
    @State private var prActionStore = PRActionStore()
    @State private var repoActionStore = RepoActionStore()
    @Environment(\.openWindow) private var openWindow
    @State private var appVM = AppViewModel()
    @State private var prsVM: PRsViewModel
    @State private var issuesVM: IssuesViewModel
    @State private var reposVM: ReposViewModel
    @State private var accountVM: AccountMenuViewModel
    /// The PR currently open in the code review (diff) screen, or nil for the
    /// normal tab list. Owned here (not in `AppViewModel`) alongside the dialogs,
    /// since the review screen replaces the whole tab content area.
    @State private var reviewing: PRRow?
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

    /// Per-tab item counts for the medium / compact tab switcher. Non-ready
    /// states count as zero, same as the page headers.
    private var tabCounts: [MainTab: Int] {
        var counts: [MainTab: Int] = [:]
        if case .ready(let rows) = prsVM.state { counts[.prs] = rows.count }
        if case .ready(let rows) = issuesVM.state { counts[.issues] = rows.count }
        if case .ready(let rows) = reposVM.state { counts[.repos] = rows.count }
        return counts
    }

    // The active tab's screen. Extracted from `body` so the SwiftUI view-builder
    // type-checker solves a smaller expression — the full `body` with all three
    // dialog overlays otherwise exceeds the "unable to type-check in reasonable
    // time" limit.
    @ViewBuilder
    private var tabContent: some View {
        if let opened = reviewing {
            // Code review (diff) screen replaces the tab list while open. Reads
            // the live row so a refresh (e.g. after an AI approve) updates the
            // header chips; falls back to the opened row if it left the cache.
            // Keyed on repo + number, not the per-fetch PR id, so switching PRs
            // rebuilds the screen + its fetch but a refresh doesn't.
            let row = prsVM.row(repoId: opened.repo.id, number: opened.pr.number) ?? opened
            PRReviewScreen(
                row: row,
                store: aiReviewStore,
                actionStore: prActionStore,
                loadFiles: { r in
                    try await services.multiApi.fetchPRFiles(
                        owner: r.repo.githubOwner,
                        repo: r.repo.githubRepo,
                        number: r.pr.number,
                        accountId: r.repo.primaryAccountId
                    ).value
                },
                accountsProvider: { await services.auth.allAccounts() },
                lastApproverProvider: { r in
                    await services.lastApprover.logins(forRepo: r.repo.id, author: r.pr.authorLogin)
                },
                onBack: { reviewing = nil },
                onApproveConfirmed: { row, approver, comment in
                    do {
                        _ = try await services.multiApi.approvePR(
                            owner: row.repo.githubOwner,
                            repo: row.repo.githubRepo,
                            number: row.pr.number,
                            body: comment,
                            accountId: approver.id
                        )
                        await services.lastApprover.record(
                            approver.login, forRepo: row.repo.id, author: row.pr.authorLogin)
                        await services.refreshNow()
                        return nil
                    } catch {
                        return "Approve failed: \(error.localizedDescription)"
                    }
                }
            )
            .id("\(row.repo.id.uuidString)#\(row.pr.number)")
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
                prActionStore: prActionStore,
                mergeAccount: { row in
                    accountsById[row.repo.primaryAccountId]
                        ?? GitHubAccount(id: row.repo.primaryAccountId, login: "unknown", host: "github.com")
                },
                onMergeConfirmed: { row in
                    do {
                        _ = try await services.multiApi.mergePR(
                            owner: row.repo.githubOwner,
                            repo: row.repo.githubRepo,
                            number: row.pr.number,
                            method: .squash
                        )
                        await services.refreshNow()
                        return nil
                    } catch {
                        return "Merge failed: \(error.localizedDescription)"
                    }
                },
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
                onReview: { reviewing = $0 },
                aiReviewPhase: { aiReviewStore.phase(for: $0) },
                onStartAIReview: { aiReviewStore.start(row: $0) },
                onStopAIReview: { aiReviewStore.stop(row: $0) },
                onDismissAIReview: { aiReviewStore.dismiss(row: $0) }
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
                repoActionStore: repoActionStore,
                onHardResetConfirmed: { row in
                    guard let status = row.status else { return "No local git status available." }
                    do {
                        let token = await services.auth.token(for: row.repo.primaryAccountId)
                        _ = try await services.gitService.hardResetToOrigin(
                            repoAt: row.repo.localPath,
                            defaultBranch: row.repo.defaultBranch,
                            token: token
                        )
                        if let merged = row.mergedBranch {
                            do {
                                try await services.gitService.deleteLocalBranch(
                                    repoAt: row.repo.localPath, branch: merged.branch)
                            } catch {
                                NSLog("Reset succeeded but couldn't delete merged branch \(merged.branch): \(error.localizedDescription)")
                            }
                        }
                        await services.refreshNow()
                        return nil
                    } catch {
                        return "Reset failed: \(error.localizedDescription)"
                    }
                },
                onDiscardConfirmed: { row in
                    do {
                        try await services.gitService.discardUnstaged(repoAt: row.repo.localPath)
                        await services.refreshNow()
                        return nil
                    } catch {
                        return "Discard failed: \(error.localizedDescription)"
                    }
                },
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
                onDiscardWorktreeConfirmed: { row, wt in
                    do {
                        try await services.gitService.discardUnstaged(repoAt: wt.path)
                        await reposVM.refresh()
                        return nil
                    } catch {
                        return "Discard failed: \(error.localizedDescription)"
                    }
                },
                onDeleteWorktreeConfirmed: { row, wt in
                    do {
                        try await services.gitService.removeWorktree(
                            wt.path, mainWorktreeAt: row.repo.localPath, force: wt.isDirty)
                        await reposVM.refresh()
                        return nil
                    } catch {
                        return "Delete failed: \(error.localizedDescription)"
                    }
                },
                onToggleApiSync: { row in
                    Task {
                        try? await services.db.repos.setApiSyncDisabled(
                            id: row.repo.id, !row.repo.apiSyncDisabled)
                        await reposVM.refresh()
                    }
                }
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
            loadFollowUp: { r in
                let conversation = try await services.multiApi.fetchPRConversation(
                    owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                    number: r.pr.number, accountId: r.repo.primaryAccountId).value
                return AIReviewFollowUp.from(conversation)
            },
            runReview: { r, diff, followUp, onLine in
                // Read the model fresh on every run (not at store construction)
                // so Settings edits apply to the next click.
                let storedModel = (try? await services.db.settings.getString(AIModelViewModel.settingsKey)) ?? nil
                let model = ClaudeModel.resolve(stored: storedModel)
                return await claude.review(
                    owner: r.repo.githubOwner, repo: r.repo.githubRepo, number: r.pr.number,
                    title: r.pr.title, author: r.pr.authorLogin, sourceBranch: r.pr.sourceBranch,
                    diff: diff, followUp: followUp, localPath: r.repo.localPath, model: model, onLine: onLine)
            },
            resolveApprover: { r in
                let accounts = await services.auth.allAccounts()
                let preferred = await services.lastApprover.logins(forRepo: r.repo.id, author: r.pr.authorLogin)
                return ApproverResolver.resolve(
                    accounts: accounts, boundAccountId: r.repo.primaryAccountId,
                    authorLogin: r.pr.authorLogin, preferredLogins: preferred)
            },
            approve: { r, approver, body in
                do {
                    _ = try await services.multiApi.approvePR(
                        owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                        number: r.pr.number, body: body, accountId: approver.id)
                    await services.lastApprover.record(approver.login, forRepo: r.repo.id, author: r.pr.authorLogin)
                    await services.refreshNow()
                    return nil
                } catch { return error.localizedDescription }
            },
            requestChanges: { r, approver, body in
                do {
                    _ = try await services.multiApi.requestChangesPR(
                        owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                        number: r.pr.number, body: body, accountId: approver.id)
                    // Remember the account here too, not just on approve: GitHub
                    // only lifts a changes-requested block when the SAME
                    // collaborator approves later, so the next review on this
                    // repo must default to this account or the PR stays stuck.
                    await services.lastApprover.record(approver.login, forRepo: r.repo.id, author: r.pr.authorLogin)
                    await services.refreshNow()
                    return nil
                } catch { return error.localizedDescription }
            })
    }

    var body: some View {
        AppFrame(
            viewModel: appVM,
            accountMenu: accountVM,
            onOpenSettings: { openWindow(id: "settings") },
            updatePhase: services.updates.phase,
            onInstallUpdate: {
                guard case .available(_, let latest) = services.updates.phase else { return }
                if UpdatePresenter.confirmInstall(latest: latest) {
                    services.updates.startInstall()
                }
            },
            onShowUpdateFailure: {
                guard case .failed(let message) = services.updates.phase else { return }
                UpdatePresenter.present(services.updates.failureIsInstall
                    ? UpdateAlertContent(installFailure: message)
                    : UpdateAlertContent(outcome: .failed(message)))
                services.updates.dismissFailure()
            },
            // The review screen replaces the tab lists, so it hides the
            // switcher (it has its own back button).
            tabBar: reviewing == nil ? MainTabBar(selection: $appVM.activeTab, counts: tabCounts) : nil
        ) {
            tabContent
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
            services.startUpdateChecks()
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

/// Hooks NSApplication lifecycle. At launch it sweeps the MCP advertisements
/// older builds left on the user's machine (see ``LegacyMCPCleanup``) — off
/// the main thread, since `~/.claude.json` can be large.
@MainActor
final class AerieAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached(priority: .utility) { LegacyMCPCleanup().run() }
    }
}
