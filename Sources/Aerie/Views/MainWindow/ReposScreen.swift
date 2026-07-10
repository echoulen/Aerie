import SwiftUI
import AppKit

/// The Repos tab's main content area. Owns no state — it renders whatever the
/// injected `ReposViewModel` reports.
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` — header style
/// mirrors `PRsScreen`, and the body stacks `RepoCard`s under it.
///
/// Action wiring:
/// - "Open" launches the repo's local path in Finder via `NSWorkspace`.
///   We prefer this over the GitHub URL because the Repos view is the
///   "local-first" surface — the GitHub side is exposed via PRs.
/// - "Hard reset" bubbles up via `onHardReset`; the shell presents
///   `DialogReset` and runs `GitService.hardResetToOrigin` on confirm. The
///   screen itself stays state-free and performs nothing destructive.
struct ReposScreen: View {
    @Bindable var viewModel: ReposViewModel
    /// When provided, the page header renders the right-aligned
    /// `SegmentedToggle` for switching between PRs and Repos (per the v2
    /// design). Snapshot tests omit it.
    var tabSelection: Binding<MainTab>? = nil
    /// The real refresh to run when the header's Refresh button is tapped.
    var onRefresh: () async -> Void = {}
    /// Opens the add-repository flow when the header's Add button is tapped.
    var onAddRepo: () -> Void = {}
    /// Asks the shell to present the hard-reset confirmation dialog for `row`.
    /// The screen owns no state, so the actual `DialogReset` presentation +
    /// `GitService.hardResetToOrigin` call live in `MainShell`.
    var onHardReset: (RepoRow) -> Void = { _ in }
    /// Asks the shell to present the discard-unstaged confirmation dialog for
    /// `row`. Like `onHardReset`, the `DialogDiscard` presentation +
    /// `GitService.discardUnstaged` call live in `MainShell`.
    var onDiscard: (RepoRow) -> Void = { _ in }
    /// Asks the shell to merge the specified worktree for `row`. Returns nil on
    /// success or an error message on failure, so the Merge button can run its
    /// idle → Merging… → Up to date feedback loop.
    var onMergeWorktree: (RepoRow, WorktreeRow) async -> String? = { _, _ in nil }
    /// Asks the shell to discard the specified worktree for `row`.
    var onDiscardWorktree: (RepoRow, WorktreeRow) -> Void = { _, _ in }
    /// Asks the shell to delete the specified worktree for `row`.
    var onDeleteWorktree: (RepoRow, WorktreeRow) -> Void = { _, _ in }
    /// The repo's PR-publish phase, looked up in the shell-owned
    /// `PRCreateStore`. Defaulted to idle for previews / snapshot tests.
    var createPhase: (RepoRow) -> PRCreatePhase = { _ in .idle }
    /// Starts a claude-driven PR publish for `row` (lives in `MainShell`,
    /// like the other repo actions — the screen stays state-free).
    var onCreatePR: (RepoRow) -> Void = { _ in }

    @Environment(\.isCompactWidth) private var isCompact
    private var pagePadding: CGFloat {
        isCompact ? AerieMetric.pagePaddingCompact : AerieMetric.pagePadding
    }

    var body: some View {
        switch viewModel.state {
        case .loading:
            nonReadyLayout { loadingView }
        case .empty:
            nonReadyLayout { emptyView }
        case .error(let msg):
            nonReadyLayout { errorView(message: msg) }
        case .ready(let rows):
            readyView(rows)
        }
    }

    // MARK: - States

    // The page header (title + meta + right-aligned tab toggle) renders in
    // every state so the `SegmentedToggle` stays reachable when there are no
    // repos yet. For non-ready states the counts collapse to 0 — the body
    // below already communicates the actual state in words.
    @ViewBuilder
    private func nonReadyLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(total: 0, withDirty: 0)
                .padding(.horizontal, pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 18)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(AerieColor.amber)
            Text("Loading repositories…")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Text("No repositories tracked")
                .aerieFont(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            Text("Add a repository in Settings to start watching it here.")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Text("Couldn't load repositories")
                .aerieFont(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            Text(message)
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.err)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ready (with content)

    @ViewBuilder
    private func readyView(_ rows: [RepoRow]) -> some View {
        let total = rows.count
        let withDirty = rows.filter { $0.status?.isDirty == true }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(total: total, withDirty: withDirty)
                    .padding(.bottom, 18)

                ForEach(rows) { row in
                    RepoCard(
                        row: row,
                        onOpen: { handleOpen(row) },
                        onHardReset: { onHardReset(row) },
                        onDiscard: { onDiscard(row) },
                        onMergeWorktree: { await onMergeWorktree(row, $0) },
                        onDiscardWorktree: { onDiscardWorktree(row, $0) },
                        onDeleteWorktree: { onDeleteWorktree(row, $0) },
                        createPhase: createPhase(row),
                        onCreatePR: { onCreatePR(row) }
                    )
                    .padding(.bottom, AerieMetric.cardGap)
                }
            }
            .padding(.horizontal, pagePadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(total: Int, withDirty: Int) -> some View {
        PageHeader(
            eyebrow: "VIEW · ⌘3",
            title: "Local repositories",
            count: "\(total) tracked · \(withDirty) with changes",
            tabSelection: tabSelection,
            onRefresh: onRefresh,
            trailing: AnyView(AddRepoButton(action: onAddRepo))
        )
    }

    // MARK: - Actions

    private func handleOpen(_ row: RepoRow) {
        NSWorkspace.shared.open(row.repo.localPath)
    }
}
