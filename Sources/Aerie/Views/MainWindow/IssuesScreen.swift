import SwiftUI
import AppKit

/// The Issues tab's main content area. Owns no state — it renders whatever the
/// injected `IssuesViewModel` reports. The issue-side mirror of ``PRsScreen``.
///
/// Visual contract: `v2/app.jsx` `IssueView` (the "Open issues" header plus the
/// stack of `IssueCard`s underneath).
///
/// Action wiring:
/// - "Open" launches the issue's HTML URL via `NSWorkspace`.
struct IssuesScreen: View {
    @Bindable var viewModel: IssuesViewModel
    /// Fixed clock injected for deterministic snapshot tests. Production callers
    /// omit this and the cards use `Date()` for the relative-time computation.
    var now: Date = Date()
    /// When provided, the page header renders the right-aligned `SegmentedToggle`
    /// for switching views. Snapshot tests omit it.
    var tabSelection: Binding<MainTab>? = nil
    /// The real refresh to run when the header's Refresh button is tapped.
    var onRefresh: () async -> Void = {}

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

    @ViewBuilder
    private func nonReadyLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(open: 0, mine: 0)
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
            Text("Loading issues…")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Text("No open issues")
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
            Text("Couldn't load issues")
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
    private func readyView(_ rows: [IssueRow]) -> some View {
        let openCount = rows.count
        let mineCount = rows.filter { $0.issue.assignedToMe }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(open: openCount, mine: mineCount)
                    .padding(.bottom, 18)

                ForEach(rows) { row in
                    IssueCard(
                        row: row,
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

    private func header(open: Int, mine: Int) -> some View {
        PageHeader(
            eyebrow: "VIEW · ⌘2",
            title: "Open issues",
            count: "\(open) open · \(mine) assigned to you",
            tabSelection: tabSelection,
            onRefresh: onRefresh
        )
    }

    // MARK: - Actions

    private func handleOpen(_ row: IssueRow) {
        NSWorkspace.shared.open(row.issue.htmlUrl)
    }
}
