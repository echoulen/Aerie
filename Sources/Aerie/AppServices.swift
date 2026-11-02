import Combine
import Foundation

extension Notification.Name {
    /// Posted (on the main actor) after a `PRSyncService` sync writes fresh PRs
    /// into `pr_cache`. The main window observes it to re-project the PRs tab.
    static let aeriePRCacheDidChange = Notification.Name("aerie.prCacheDidChange")
    /// Posted (on the main actor) after an `IssueSyncService` sync writes fresh
    /// issues into `issue_cache`. The main window observes it to re-project the
    /// Issues tab.
    static let aerieIssueCacheDidChange = Notification.Name("aerie.issueCacheDidChange")
    /// Posted (on the main actor) after the tracked repo set changes — a repo is
    /// added or removed via Settings. The main window observes it to re-project
    /// the Repos tab (and kick a sync) so a newly-added repo appears straight
    /// away rather than waiting for the next polling tick.
    static let aerieReposDidChange = Notification.Name("aerie.reposDidChange")
}

/// Cross-window navigation intent. The main window's "Add repository" button
/// lives in a different SwiftUI scene from the Settings window, so it can't push
/// state directly. It sets a pending request here and opens the Settings window;
/// `SettingsWindow` consumes the request on appear (jumping to Repositories and
/// opening the add-repo sheet), then clears it.
@MainActor
@Observable
final class SettingsNavigator {
    /// When set, `SettingsWindow` should select this route on next appearance.
    var pendingRoute: SettingsRoute?
    /// When true, `SettingsWindow` should present the add-repo sheet on next
    /// appearance.
    var pendingAddRepo: Bool = false

    /// Requests that Settings open straight onto Repositories with the add-repo
    /// sheet presented. Call this immediately before `openWindow(id:"settings")`.
    func requestAddRepo() {
        pendingRoute = .repositories
        pendingAddRepo = true
    }

    /// Reads and clears the pending request in one shot, so it fires exactly
    /// once even if `SettingsWindow` re-appears later.
    func consume() -> (route: SettingsRoute?, showAddRepo: Bool) {
        defer { pendingRoute = nil; pendingAddRepo = false }
        return (pendingRoute, pendingAddRepo)
    }
}

/// Process-wide singleton that owns the long-lived services and shares them
/// between the main window scene and the Settings window scene (SwiftUI's
/// `WindowGroup` + `Window` scenes don't share `@State`, so we hoist the
/// services here).
///
/// Polling orchestration is wired here: the scheduler's single per-repo refresh
/// closure drives BOTH `PRSyncService` (PRs tab) and `GitStatusRefresher`
/// (Repos tab) for each repo, and `startPolling()` follows app focus.
@MainActor
final class AppServices {
    static let shared: AppServices = {
        do {
            return try AppServices()
        } catch {
            fatalError("Failed to initialize AppServices: \(error)")
        }
    }()

    let db: AppDatabase
    let auth: LiveAuthService
    let apiClient: LiveGitHubAPIClient
    let multiApi: MultiAccountAPI
    let prSync: PRSyncService
    let issueSync: IssueSyncService
    let gitService: any GitService
    /// Gates the poller's git status reads on FSEvents; `refreshNow()` marks
    /// every tree changed so the manual button always re-reads.
    let workingTreeWatcher: WorkingTreeWatcher
    let scheduler: PollingScheduler
    let focusObserver: any AppFocusObserver
    /// Cross-window navigation intents (e.g. the main window asking Settings to
    /// open the add-repo sheet). Shared so both scenes see the same instance.
    let settingsNavigator = SettingsNavigator()
    /// App-update lifecycle (titlebar pill + the "Check for Updates…" menu
    /// item). Lives here so both scenes read one state and the periodic check
    /// outlives any single window.
    let updates = UpdateStore()

    /// Background state for the PR-scoped actions (Merge, Approve). Held here,
    /// not in the main window, so a merge started from the phone shows on the
    /// desktop card and survives the main window closing.
    let prActionStore = PRActionStore()
    /// AI-review runs for every PR, shared by the desktop and the phone.
    private(set) lazy var aiReviewStore: AIReviewStore = makeAIReviewStore()
    /// The phone backend (off unless enabled in Settings · Mobile).
    private(set) lazy var mobile: MobileController = MobileController(services: self)

    /// Per-repo (and per-repo + author) memory of the account the last approval was submitted as. Used to
    /// default the approver picker (manual + AI Review) to the user's last choice.
    var lastApprover: LastApproverStore { LastApproverStore(settings: db.settings) }

    /// Fires after each polling tick upserts fresh git status. The main shell
    /// subscribes (throttled) to re-read its `ReposViewModel` so the cards
    /// reflect the live branch / dirty state without a manual refresh.
    let gitStatusDidChange: PassthroughSubject<Void, Never>

    /// Retains the focus→update-check subscription created by
    /// `startUpdateChecks()`, and gates its idempotency.
    private var updateFocusSubscription: AnyCancellable?

    /// Retains the focus→scheduler subscription created by `startPolling()`.
    /// Held here (rather than in a view) because the polling lifecycle must
    /// outlive any single window. Also gates `startPolling()`'s idempotency.
    private var focusSubscription: AnyCancellable?

    private init() throws {
        let db = try AppDatabase(url: AppDatabase.defaultURL())
        // Pass the AccountDAO so bootstrap can reconcile discovered gh
        // accounts into the persistence layer — without this, the Settings ·
        // Accounts screen reads an empty table and always shows zero rows
        // even when `gh` is fully authenticated.
        let auth = LiveAuthService(accountStore: db.accounts)
        let client = LiveGitHubAPIClient()

        let tokensByAccount: @Sendable () async -> [UUID: String] = { [auth] in
            let accounts = await auth.allAccounts()
            var map: [UUID: String] = [:]
            for account in accounts {
                if let token = await auth.token(for: account.id) {
                    map[account.id] = token
                }
            }
            return map
        }
        let accountsInOrder: @Sendable () async -> [UUID] = { [auth] in
            await auth.allAccounts().map(\.id)
        }

        let multiApi = MultiAccountAPI(
            client: client,
            tokensByAccount: tokensByAccount,
            accountsInOrder: accountsInOrder
        )

        // Polling orchestration. The scheduler owns a SINGLE per-repo refresh
        // closure, so it must drive both sides for each repo:
        //   * PR fetch → cache: `prSync.sync` posts `.aeriePRCacheDidChange`
        //     (on main, via `onChange`) so the PRs tab re-projects.
        //   * Local git status: `refresher.refresh` upserts `gitStatusCache`
        //     (gated by the FSEvents watcher — an unchanged tree isn't re-read).
        //     Once the whole tick has settled we signal `gitStatusDidChange`
        //     (on main — `PassthroughSubject` `.send()` isn't thread-safe) so
        //     the Repos tab re-reads exactly once per tick.
        // All captured values are Sendable (actors / value types / lock-guarded
        // classes), so they're safe inside the scheduler's `@Sendable` closure.
        let gitService = LiveGitService()
        let workingTreeWatcher = WorkingTreeWatcher()
        let prSync = PRSyncService(db: db, api: multiApi, git: gitService, onChange: {
            await MainActor.run {
                NotificationCenter.default.post(name: .aeriePRCacheDidChange, object: nil)
            }
        })
        let issueSync = IssueSyncService(db: db, api: multiApi, onChange: {
            await MainActor.run {
                NotificationCenter.default.post(name: .aerieIssueCacheDidChange, object: nil)
            }
        })
        let refresher = GitStatusRefresher(db: db, gitService: gitService, changes: workingTreeWatcher)
        let mergedSync = MergedBranchSync(db: db, api: multiApi)
        let statusSubject = PassthroughSubject<Void, Never>()
        let scheduler = PollingScheduler(
            clock: LiveClock(),
            refresh: { [prSync, issueSync, refresher, mergedSync] repoId in
                await prSync.sync(repoId: repoId)
                await issueSync.sync(repoId: repoId)
                await refresher.refresh(repoId: repoId)
                await mergedSync.sync(repoId: repoId)
            },
            onTickComplete: { [statusSubject] in
                await MainActor.run { statusSubject.send() }
            }
        )
        let focusObserver = LiveAppFocusObserver()

        self.db = db
        self.auth = auth
        self.apiClient = client
        self.multiApi = multiApi
        self.prSync = prSync
        self.issueSync = issueSync
        self.gitService = gitService
        self.workingTreeWatcher = workingTreeWatcher
        self.scheduler = scheduler
        self.focusObserver = focusObserver
        self.gitStatusDidChange = statusSubject
    }

    /// Starts focus-driven polling: the scheduler runs continuously and slows
    /// to a quarter of the configured cadence while the app is backgrounded
    /// (see `PollingScheduler.setAppActive`), rather than pausing outright.
    /// On the first `active` signal it ticks immediately (every repo is due),
    /// so the PRs and Repos tabs populate shortly after launch and stay fresh
    /// on the configured cadence. Idempotent — the main window calls it on
    /// appear, and repeat calls are no-ops.
    func startPolling() {
        guard focusSubscription == nil else { return }
        focusSubscription = scheduler.attachFocusObserver(focusObserver) { [db] in
            ((try? await db.repos.all()) ?? []).filter { !$0.hidden }.map(\.id)
        }

        // Apply the user's persisted cadences so the loop ticks at the
        // configured rate (not the 30/300 defaults) once past the first tick.
        Task { [scheduler, db] in
            let active = (try? await db.settings.getInt("polling.active_seconds")) ?? nil
            let background = (try? await db.settings.getInt("polling.background_seconds")) ?? nil
            await scheduler.setCadences(
                active: TimeInterval(active ?? 30),
                background: TimeInterval(background ?? 300)
            )
        }
    }

    /// Starts update checking: once now, every six hours after that, and again
    /// whenever the app returns to the foreground (throttled inside
    /// `UpdateStore`). The focus signal is what keeps the titlebar honest — a
    /// release published minutes after launch would otherwise stay invisible
    /// until the next six-hour tick. Idempotent.
    func startUpdateChecks() {
        updates.startChecking()
        guard updateFocusSubscription == nil else { return }
        updateFocusSubscription = focusObserver.isActive
            .filter { $0 }
            .sink { [updates] _ in
                Task { @MainActor in await updates.refreshOnFocus() }
            }
    }

    /// Forces an immediate refresh of every non-hidden repo, bypassing the
    /// polling cadence. Drives the scheduler's per-repo closure (PRs + issues +
    /// git status) in one pass; the resulting `.aeriePRCacheDidChange` /
    /// `.aerieIssueCacheDidChange` / `gitStatusDidChange` signals re-project the
    /// open views. Backs the page header's manual Refresh button. Returns once
    /// every repo's fetch has settled, so the button can spin until then.
    func refreshNow() async {
        // A manual refresh must always re-read status, changed or not.
        workingTreeWatcher.markAllChanged()
        let repoIds = ((try? await db.repos.all()) ?? []).filter { !$0.hidden }.map(\.id)
        await scheduler.refreshNow(repoIds: repoIds, now: Date())
    }

    /// Re-syncs the one repo an action just touched — the scheduler's usual
    /// per-repo pass — without waiting for it, so the action's spinner ends
    /// when the action itself lands. (`refreshNow` re-syncs every repo and
    /// forces every working-tree walk: awaiting it after an approve kept the
    /// key spinning 6–15 s.) Pass `treeChanged` when the action rewrote the
    /// working tree, so status is re-read before FSEvents reports the writes.
    func refreshInBackground(_ repo: Repository, treeChanged: Bool = false) {
        if treeChanged { workingTreeWatcher.markChanged(at: repo.localPath) }
        let scheduler = self.scheduler
        Task { await scheduler.refreshNow(repoIds: [repo.id], now: Date()) }
    }

    // MARK: - PR actions (shared by the desktop and the phone)

    /// Which accounts may approve `row`, defaulting to the last approver
    /// remembered for its repo + author. Shared by the review screen's and
    /// PR list's Approve dialogs, the AI-review auto-approve, and the phone.
    func resolveApprovers(_ row: PRRow) async -> ApproverResolution {
        let accounts = await auth.allAccounts()
        let preferred = await lastApprover.logins(forRepo: row.repo.id, author: row.pr.authorLogin)
        return ApproverResolver.resolve(
            accounts: accounts, boundAccountId: row.repo.primaryAccountId,
            authorLogin: row.pr.authorLogin, preferredLogins: preferred)
    }

    /// Submits a confirmed approving review (the Approve dialog's `onConfirm`
    /// body), remembers the approver, and re-syncs its repo in the background.
    /// Returns an error message on failure, nil on success.
    func approveConfirmed(_ row: PRRow, _ approver: GitHubAccount, _ comment: String?) async -> String? {
        do {
            _ = try await multiApi.approvePR(
                owner: row.repo.githubOwner,
                repo: row.repo.githubRepo,
                number: row.pr.number,
                body: comment,
                accountId: approver.id
            )
            await lastApprover.record(
                approver.login, forRepo: row.repo.id, author: row.pr.authorLogin)
            refreshInBackground(row.repo)
            return nil
        } catch {
            return "Approve failed: \(error.localizedDescription)"
        }
    }

    enum MergeOutcome: Equatable {
        case merged(sha: String)
        case failed(String)
    }

    /// Squash-merges a confirmed PR (the Merge dialog's `onConfirm` body) and
    /// re-syncs its repo.
    func mergeConfirmed(_ row: PRRow) async -> MergeOutcome {
        do {
            let result = try await multiApi.mergePR(
                owner: row.repo.githubOwner,
                repo: row.repo.githubRepo,
                number: row.pr.number,
                method: .squash
            )
            refreshInBackground(row.repo)
            await prSync.scheduleResync(repoId: row.repo.id)
            return .merged(sha: result.value.sha)
        } catch {
            // A refused merge means the row was stale: re-sync so
            // the card shows why (e.g. Conflicts), not just the error.
            refreshInBackground(row.repo)
            return .failed("Merge failed: \(error.localizedDescription)")
        }
    }

    /// Builds the AI-review store, wiring its closures to live services.
    private func makeAIReviewStore() -> AIReviewStore {
        let claude: ClaudeReviewService = LiveClaudeReviewService()
        return AIReviewStore(
            loadFiles: { [unowned self] r in
                try await multiApi.fetchPRFiles(
                    owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                    number: r.pr.number, accountId: r.repo.primaryAccountId).value
            },
            loadFollowUp: { [unowned self] r in
                let conversation = try await multiApi.fetchPRConversation(
                    owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                    number: r.pr.number, accountId: r.repo.primaryAccountId).value
                return AIReviewFollowUp.from(conversation)
            },
            runReview: { [unowned self] r, diff, followUp, onLine in
                // Read the model and guidance fresh on every run (not at store construction)
                // so Settings edits apply to the next click.
                let storedModel = (try? await db.settings.getString(AIModelViewModel.settingsKey)) ?? nil
                let model = ClaudeModel.resolve(stored: storedModel)
                let guidance = AIReviewGuidance.resolve(
                    firstPass: (try? await db.settings.getString(AIReviewGuidance.firstPassKey)) ?? nil,
                    followUp: (try? await db.settings.getString(AIReviewGuidance.followUpKey)) ?? nil)
                return await claude.review(
                    owner: r.repo.githubOwner, repo: r.repo.githubRepo, number: r.pr.number,
                    title: r.pr.title, author: r.pr.authorLogin, sourceBranch: r.pr.sourceBranch,
                    diff: diff, followUp: followUp, guidance: guidance,
                    localPath: r.repo.localPath, model: model, onLine: onLine)
            },
            resolveApprover: { [unowned self] in await resolveApprovers($0) },
            approve: { [unowned self] r, approver, body in
                do {
                    _ = try await multiApi.approvePR(
                        owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                        number: r.pr.number, body: body, accountId: approver.id)
                    await lastApprover.record(approver.login, forRepo: r.repo.id, author: r.pr.authorLogin)
                    refreshInBackground(r.repo)
                    return nil
                } catch { return error.localizedDescription }
            },
            requestChanges: { [unowned self] r, approver, body in
                do {
                    _ = try await multiApi.requestChangesPR(
                        owner: r.repo.githubOwner, repo: r.repo.githubRepo,
                        number: r.pr.number, body: body, accountId: approver.id)
                    // Remember the account here too, not just on approve: GitHub
                    // only lifts a changes-requested block when the SAME
                    // collaborator approves later, so the next review on this
                    // repo must default to this account or the PR stays stuck.
                    await lastApprover.record(approver.login, forRepo: r.repo.id, author: r.pr.authorLogin)
                    refreshInBackground(r.repo)
                    return nil
                } catch { return error.localizedDescription }
            })
    }
}
