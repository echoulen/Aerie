import SwiftUI
import AppKit

/// The PRs tab's main content area. Owns no state — it renders whatever the
/// injected `PRsViewModel` reports.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `PRView` (the section
/// titled "Open pull requests" plus the stack of `PRCard`s underneath).
///
/// Action wiring:
/// - "Open" launches the PR's HTML URL via `NSWorkspace`.
/// - "Merge" is fully owned by `PRCard`: it presents `DialogMerge` as a
///   popover and, on confirm, hands off to the shared `prActionStore`, which
///   runs `onMergeConfirmed` (the `MultiAccountAPI.mergePR` call, owned by
///   `MainShell`) in the background. The screen itself stays state-free and
///   performs nothing destructive (mirrors `ReposScreen`'s `onHardReset`).
struct PRsScreen: View {
    @Bindable var viewModel: PRsViewModel
    /// Fixed clock injected for deterministic snapshot tests. Production
    /// callers omit this and the cards use `Date()` for the relative-time
    /// computation.
    var now: Date = Date()
    /// When provided, the page header renders the right-aligned
    /// `SegmentedToggle` for switching between PRs and Repos (per the v2
    /// design). Snapshot tests omit it.
    var tabSelection: Binding<MainTab>? = nil
    /// The real refresh to run when the header's Refresh button is tapped.
    var onRefresh: () async -> Void = {}
    /// Background store for Merge/Approve/Force-checkout — passed straight
    /// through to each `PRCard`.
    var prActionStore: PRActionStore = PRActionStore()
    /// Resolves the GitHub account a merge confirmation displays as acting.
    var mergeAccount: (PRRow) -> GitHubAccount = { row in
        GitHubAccount(id: row.repo.primaryAccountId, login: "unknown", host: "github.com")
    }
    /// Runs the actual squash-merge for a confirmed row. The `MultiAccountAPI`
    /// call + refresh live in `MainShell`.
    var onMergeConfirmed: (PRRow) async -> String? = { _ in nil }
    /// Runs the base-branch update for a PR's checkout (the status-row "Update
    /// branch" pill). Async so the pill can spin until the row re-syncs; the
    /// `GitService.updateBranchFromBase` call + refresh live in `MainShell`.
    var onUpdateBranch: (PRRow) async -> Void = { _ in }
    /// Runs the actual force-checkout for a confirmed row. The
    /// `GitService.forceCheckout` call + refresh live in `MainShell`.
    var onCheckoutConfirmed: (PRRow) async -> String? = { _ in nil }
    /// Asks the shell to open the code review screen for `row`. The detail-page
    /// navigation state (`reviewing`) lives in `MainShell` (mirrors `onMerge`).
    var onReview: (PRRow) -> Void = { _ in }
    /// Current AI-review lifecycle for `row` — drives the card's own "AI
    /// Review" button so it can start (and show progress for) a review right
    /// from the list. Reads `AIReviewStore`; defaulted to `.idle` for
    /// snapshot tests and previews.
    var aiReviewPhase: (PRRow) -> AIReviewPhase = { _ in .idle }
    /// Starts an AI review for `row` directly from the list. Wraps
    /// `AIReviewStore.start(row:)`; defaulted to a no-op for snapshot tests
    /// and previews.
    var onStartAIReview: (PRRow) -> Void = { _ in }
    /// Clears a failed AI-review phase for `row` back to idle. Wraps
    /// `AIReviewStore.dismiss(row:)`; defaulted to a no-op for snapshot tests
    /// and previews.
    var onDismissAIReview: (PRRow) -> Void = { _ in }

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
    // PRs yet. For non-ready states the counts collapse to 0 — the body below
    // already communicates the actual state in words.
    @ViewBuilder
    private func nonReadyLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(open: 0, ready: 0)
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
            Text("Loading pull requests…")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Text("No open pull requests")
                .aerieFont(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            Text("Add a repository or wait for the next polling tick.")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Text("Couldn't load pull requests")
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
    private func readyView(_ rows: [PRRow]) -> some View {
        let openCount = rows.count
        let readyCount = rows.filter {
            $0.pr.state == .open && $0.pr.ciState == .success && $0.pr.reviewState == .approved
        }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(open: openCount, ready: readyCount)
                    .padding(.bottom, 18)

                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    PRCard(
                        row: row,
                        prActionStore: prActionStore,
                        mergeAccount: mergeAccount,
                        onMergeConfirmed: onMergeConfirmed,
                        onOpen: { handleOpen(row) },
                        onCheckoutConfirmed: onCheckoutConfirmed,
                        onReview: { onReview(row) },
                        aiReviewPhase: aiReviewPhase(row),
                        onStartAIReview: { onStartAIReview(row) },
                        onDismissAIReview: { onDismissAIReview(row) },
                        onUpdateBranch: { await onUpdateBranch(row) },
                        now: now
                    )
                    .padding(.bottom, AerieMetric.cardGap)
                }
            }
            .padding(.horizontal, pagePadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(open: Int, ready: Int) -> some View {
        PageHeader(
            eyebrow: "VIEW · ⌘1",
            title: "Open pull requests",
            count: "\(open) open · \(ready) ready to merge",
            tabSelection: tabSelection,
            onRefresh: onRefresh
        )
    }

    // MARK: - Actions

    private func handleOpen(_ row: PRRow) {
        NSWorkspace.shared.open(row.pr.htmlUrl)
    }
}
