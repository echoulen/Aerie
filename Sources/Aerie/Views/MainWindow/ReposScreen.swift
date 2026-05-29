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
/// - "Hard reset" leaves a TODO log line for now. The full reset
///   confirmation dialog (`DialogReset`) lands in Phase 17.2; until then,
///   this view emits nothing destructive.
struct ReposScreen: View {
    @Bindable var viewModel: ReposViewModel
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
    // repos yet. For non-ready states the counts collapse to 0 — the body
    // below already communicates the actual state in words.
    @ViewBuilder
    private func nonReadyLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(total: 0, withDirty: 0)
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
            Text("Loading repositories…")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Text("No repositories tracked")
                .font(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            Text("Add a repository in Settings to start watching it here.")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Text("Couldn't load repositories")
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
                        onHardReset: { handleHardReset(row) }
                    )
                    .padding(.bottom, AerieMetric.cardGap)
                }
            }
            .padding(.horizontal, AerieMetric.pagePadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(total: Int, withDirty: Int) -> some View {
        PageHeader(
            eyebrow: "VIEW · ⌘2",
            title: "Local repositories",
            count: "\(total) tracked · \(withDirty) with changes",
            tabSelection: tabSelection
        )
    }

    // MARK: - Actions

    private func handleOpen(_ row: RepoRow) {
        NSWorkspace.shared.open(row.repo.localPath)
    }

    private func handleHardReset(_ row: RepoRow) {
        // TODO(phase-17.2): show DialogReset confirmation + invoke ResetService.
        // For now, log intent only so we don't perform a destructive action.
        print("[ReposScreen] Hard reset requested for \(row.repo.name) — DialogReset lands in Phase 17.2.")
    }
}
