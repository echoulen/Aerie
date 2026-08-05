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
/// - "Hard reset" is fully owned by `RepoCard`: it presents `DialogReset` as a
///   popover and, on confirm, hands off to the shared `repoActionStore`, which
///   runs `onHardResetConfirmed` (the `GitService.hardResetToOrigin` call,
///   owned by `MainShell`) in the background. The screen itself stays
///   state-free and performs nothing destructive.
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
    var repoActionStore: RepoActionStore = RepoActionStore()
    var onHardResetConfirmed: (RepoRow) async -> String? = { _ in nil }
    /// Runs the actual discard-unstaged (`git restore .` + `git clean -fd`) for
    /// `row`. Returns an error message on failure, nil on success.
    var onDiscardConfirmed: (RepoRow) async -> String? = { _ in nil }
    /// Asks the shell to merge the specified worktree for `row`. Returns nil on
    /// success or an error message on failure, so the Merge button can run its
    /// idle → Merging… → Up to date feedback loop.
    var onMergeWorktree: (RepoRow, WorktreeRow) async -> String? = { _, _ in nil }
    /// Asks the shell to discard the specified worktree for `row`.
    var onDiscardWorktreeConfirmed: (RepoRow, WorktreeRow) async -> String? = { _, _ in nil }
    /// Asks the shell to delete the specified worktree for `row`.
    var onDeleteWorktree: (RepoRow, WorktreeRow) -> Void = { _, _ in }
    /// The repo's PR-publish phase, looked up in the shell-owned
    /// `PRCreateStore`. Defaulted to idle for previews / snapshot tests.
    var createPhase: (RepoRow) -> PRCreatePhase = { _ in .idle }
    /// Starts a claude-driven PR publish for `row` (lives in `MainShell`,
    /// like the other repo actions — the screen stays state-free).
    var onCreatePR: (RepoRow) -> Void = { _ in }
    /// Pauses or resumes `row`'s GitHub API sync (lives in `MainShell`, like
    /// the other repo actions — the screen stays state-free).
    var onToggleApiSync: (RepoRow) -> Void = { _ in }

    @Environment(\.isCompactWidth) private var isCompact
    private var pagePadding: CGFloat {
        isCompact ? AerieMetric.pagePaddingCompact : AerieMetric.pagePadding
    }

    // Drag-reorder state, mirroring Settings' RepositoriesScreen but with
    // per-card measured heights (cards are content-driven in height, so the
    // uniform-rowHeight maths there doesn't transfer). `cardHeights` freezes
    // during a drag so animating layout can't feed back into slot maths.
    @State private var draggingId: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragTarget: Int?
    @State private var cardHeights: [UUID: CGFloat] = [:]

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

                if let actionError = viewModel.actionError {
                    Text(actionError)
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.err)
                        .padding(.bottom, 10)
                }

                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    let dragging = draggingId == row.id
                    RepoCard(
                        row: row,
                        onOpen: { handleOpen(row) },
                        repoActionStore: repoActionStore,
                        onHardResetConfirmed: onHardResetConfirmed,
                        onDiscardConfirmed: onDiscardConfirmed,
                        onMergeWorktree: { await onMergeWorktree(row, $0) },
                        onDiscardWorktreeConfirmed: { await onDiscardWorktreeConfirmed(row, $0) },
                        onDeleteWorktree: { onDeleteWorktree(row, $0) },
                        createPhase: createPhase(row),
                        onCreatePR: { onCreatePR(row) },
                        onToggleApiSync: { onToggleApiSync(row) },
                        onRemove: { Task { await viewModel.remove(id: row.repo.id) } }
                    )
                    .padding(.bottom, AerieMetric.cardGap)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if draggingId == nil { cardHeights[row.id] = h }
                    }
                    .offset(y: cardOffset(idx: idx, rows: rows, isDragging: dragging))
                    .shadow(color: .black.opacity(dragging ? 0.28 : 0),
                            radius: dragging ? 12 : 0, y: dragging ? 6 : 0)
                    .zIndex(dragging ? 1 : 0)
                    // Dragged card follows the cursor 1:1 (animation ignores
                    // dragTranslation); bystanders spring only on discrete
                    // dragTarget changes — same anti-judder split as Settings.
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: dragTarget)
                    .gesture(reorderGesture(row: row, rows: rows))
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

    // MARK: - Drag-reorder

    /// Hold (~0.35 s) then drag. Sequencing keeps ordinary clicks and the
    /// card's buttons working — only a held press enters reorder mode.
    /// `.global` coordinate space is critical: the card moves via `.offset`,
    /// so a local-space drag would feed its own offset back into the
    /// translation and oscillate (same lesson as Settings' grip).
    private func reorderGesture(row: RepoRow, rows: [RepoRow]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if draggingId == nil { draggingId = row.id }
                dragTranslation = drag?.translation.height ?? 0
                updateDragTarget(rows: rows)
            }
            .onEnded { _ in commitDrag(rows: rows) }
    }

    private func height(of id: UUID) -> CGFloat {
        cardHeights[id] ?? 120
    }

    /// Signed distance from the dragged card's origin to its settled position
    /// in slot `to` — the sum of the heights of the cards it crosses.
    /// (`cardHeights` already includes the inter-card gap; see readyView.)
    private func slotDistance(from: Int, to: Int, rows: [RepoRow]) -> CGFloat {
        if to > from { return rows[(from + 1)...to].reduce(0) { $0 + height(of: $1.id) } }
        if to < from { return -rows[to..<from].reduce(0) { $0 + height(of: $1.id) } }
        return 0
    }

    /// Picks the slot whose settled offset is nearest the live translation,
    /// with hysteresis: only switch when the new slot is closer by 20% of the
    /// crossed card's height, so a hand resting near a boundary doesn't make
    /// the bystander cards flip-flop.
    private func updateDragTarget(rows: [RepoRow]) {
        guard let id = draggingId,
              let from = rows.firstIndex(where: { $0.id == id }) else { return }
        let current = dragTarget ?? from
        var candidate = current
        var candidateDist = abs(dragTranslation - slotDistance(from: from, to: current, rows: rows))
        for t in rows.indices {
            let d = abs(dragTranslation - slotDistance(from: from, to: t, rows: rows))
            if d < candidateDist { candidate = t; candidateDist = d }
        }
        guard candidate != current else { return }
        let dead = height(of: rows[candidate].id) * 0.2
        let currentDist = abs(dragTranslation - slotDistance(from: from, to: current, rows: rows))
        if currentDist - candidateDist > dead { dragTarget = candidate }
    }

    /// Bystander offset: cards between the dragged card's origin and target
    /// shift by the DRAGGED card's height (the gap being opened/closed always
    /// matches the dragged card, not the bystander).
    private func cardOffset(idx: Int, rows: [RepoRow], isDragging: Bool) -> CGFloat {
        if isDragging { return dragTranslation }
        guard let id = draggingId,
              let from = rows.firstIndex(where: { $0.id == id }),
              let to = dragTarget else { return 0 }
        let step = height(of: id)
        if from < to, idx > from, idx <= to { return -step }
        if from > to, idx >= to, idx < from { return step }
        return 0
    }

    /// On release: apply the move optimistically and clear drag state inside
    /// one animation, so the card springs into its new slot (same shape as
    /// Settings' commitDrag).
    private func commitDrag(rows: [RepoRow]) {
        let from = draggingId.flatMap { id in rows.firstIndex(where: { $0.id == id }) }
        let to = dragTarget
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if let from, let to, to != from {
                viewModel.applyReorder(from: from, to: to >= from ? to + 1 : to)
            }
            draggingId = nil
            dragTranslation = 0
            dragTarget = nil
        }
    }
}
