import SwiftUI
import AppKit

/// The PRs tab's main content area. Owns no state — it renders whatever the
/// injected `PRsViewModel` reports.
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` (the section
/// titled "Open pull requests" plus the stack of `PRCard`s underneath).
///
/// Action wiring:
/// - "Open" launches the PR's HTML URL via `NSWorkspace`.
/// - "Merge" leaves a TODO log line for now. The full merge confirmation
///   dialog (`DialogMerge`) lands in Phase 17; until then, this view emits
///   nothing destructive — the placeholder closure just logs intent.
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
            header(open: 0, repos: 0, mine: 0)
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
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Text("No open pull requests")
                .font(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            Text("Add a repository or wait for the next polling tick.")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Text("Couldn't load pull requests")
                .font(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            Text(message)
                .font(AerieFont.small())
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
        let repoCount = Set(rows.map { $0.repo.id }).count
        let mineCount = rows.filter { $0.pr.isMine }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(open: openCount, repos: repoCount, mine: mineCount)
                    .padding(.bottom, 18)

                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    PRCard(
                        row: row,
                        onMerge: { handleMerge(row) },
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

    private func header(open: Int, repos: Int, mine: Int) -> some View {
        HStack(alignment: .bottom) {
            // Title + count share one baseline-aligned row (design `Header`),
            // matching the Repositories view — not stacked.
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Open pull requests")
                    .font(AerieFont.display())
                    .foregroundStyle(AerieColor.text1)
                Text("\(open) open · across \(repos) \(repos == 1 ? "repository" : "repositories") · \(mine) mine")
                    .font(AerieFont.eyebrow())
                    .foregroundStyle(AerieColor.text4)
                    .tracking(0.8)
            }
            Spacer(minLength: 16)
            if let tabSelection {
                SegmentedToggle(selection: tabSelection)
            }
        }
        .padding(.top, 28)
    }

    // MARK: - Actions

    private func handleOpen(_ row: PRRow) {
        NSWorkspace.shared.open(row.pr.htmlUrl)
    }

    private func handleMerge(_ row: PRRow) {
        // TODO(phase-17): show DialogMerge confirmation + invoke MergeService.
        // For now, log intent only so we don't perform a destructive action.
        print("[PRsScreen] Merge requested for \(row.repo.name) #\(row.pr.number) — DialogMerge lands in Phase 17.")
    }
}
