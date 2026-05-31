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
/// - "Merge" bubbles up via `onMerge`; the shell presents `DialogMerge` and
///   runs `MultiAccountAPI.mergePR` on confirm. The screen itself stays
///   state-free and performs nothing destructive (mirrors `ReposScreen`'s
///   `onHardReset`).
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
    /// Asks the shell to present the merge confirmation dialog for `row`.
    /// The screen owns no state, so the actual `DialogMerge` presentation +
    /// `MultiAccountAPI.mergePR` call live in `MainShell`.
    var onMerge: (PRRow) -> Void = { _ in }

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
                .padding(.horizontal, AerieMetric.pagePadding)
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
                        onMerge: { onMerge(row) },
                        onOpen: { handleOpen(row) },
                        now: now
                    )
                    .padding(.bottom, AerieMetric.cardGap)
                }
            }
            .padding(.horizontal, AerieMetric.pagePadding)
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
