import SwiftUI

/// Settings → Repositories main content.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` lines 200-310.
/// Layout:
///   ┌──────────────────────────────────────────────────────────┐
///   │ Repositories            [Refresh all] [+ Add repository] │
///   │                                                          │
///   │ ┌──────────────────────────────────────────────────────┐ │
///   │ │ RepoSettingsRow #1                                   │ │
///   │ │ ─────────────────────────────────────────────────────│ │
///   │ │ RepoSettingsRow #2                                   │ │
///   │ │ ─────────────────────────────────────────────────────│ │
///   │ │ RepoSettingsRow #3                                   │ │
///   │ └──────────────────────────────────────────────────────┘ │
///   └──────────────────────────────────────────────────────────┘
///
/// Drag-to-reorder: the `⠿` grip on each row carries a `DragGesture` (see
/// `RepoSettingsRow`) that reports its vertical translation here. We map that to
/// a target slot against a measured row height, slide the dragged row under the
/// cursor while the rows it passes spring aside, and on release settle the new
/// order optimistically via `viewModel.applyReorder(from:to:)`. The list is a
/// custom `VStack`/`ForEach` (not a `List`), so `.onMove` isn't available —
/// hence the hand-rolled gesture.
struct RepositoriesScreen: View {
    @Bindable var viewModel: RepositoriesViewModel
    var onRefreshAll: () -> Void
    var onAddRepo: () -> Void

    // Drag-reorder state. `draggingId` marks the grabbed row, `dragTranslation`
    // is its live vertical offset, and `rowHeight` (measured from the first row)
    // converts a drag distance into a number of slots moved.
    @State private var draggingId: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragTarget: Int?
    @State private var rowHeight: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                if !viewModel.repos.isEmpty {
                    columnLegend.padding(.top, 20)
                    listCard.padding(.top, 6)
                }
                if let error = viewModel.error {
                    Text(error)
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.err)
                        .padding(.top, 18)
                }
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionEyebrow("REPOSITORIES")
            HStack(alignment: .firstTextBaseline) {
                Text("Tracked locally")
                    .aerieFont(AerieFont.sectionTitle())
                    .foregroundStyle(AerieColor.text1)
                Text("\(viewModel.repos.count) repositor\(viewModel.repos.count == 1 ? "y" : "ies")")
                    .aerieFont(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 16)
                Button("↻ Refresh all", action: onRefreshAll)
                    .buttonStyle(GhostButtonStyle())
                Button("+ Add repository", action: onAddRepo)
                    .buttonStyle(AmberButtonStyle())
            }
        }
    }

    // MARK: - Column legend

    // Faint guide above the list — `settings.jsx` lines 233-245. Same 5-column
    // grid as the rows, inset 20 pt to sit over the row content (the rows pad
    // 20 pt inside the card).
    private var columnLegend: some View {
        HStack(spacing: 18) {
            Color.clear.frame(width: 18, height: 1)
            legendLabel("NAME · PATH")
                .frame(maxWidth: .infinity, alignment: .leading)
            legendLabel("GITHUB · CURRENT BRANCH")
                .frame(maxWidth: .infinity, alignment: .leading)
            legendLabel("ACCOUNT")
                .frame(width: 130, alignment: .leading)
            Color.clear.frame(width: 28, height: 1)
        }
        .padding(.horizontal, 20)
    }

    private func legendLabel(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.custom(.mono, size: 9).weight(.medium))
            .tracking(1.8) // 0.20em × 9 px
            .foregroundStyle(AerieColor.text4)
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.eyebrow())
            .tracking(2.0)
            .foregroundStyle(AerieColor.text4)
    }

    // MARK: - List

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.repos.enumerated()), id: \.element.id) { idx, repo in
                if idx > 0 {
                    Rectangle()
                        .fill(AerieColor.glassLine)
                        .frame(height: 1)
                        // Hide separators mid-drag so they don't tear as rows
                        // slide past one another.
                        .opacity(draggingId == nil ? 1 : 0)
                }
                row(idx: idx, repo: repo)
            }
        }
        .glass(.card)
    }

    @ViewBuilder
    private func row(idx: Int, repo: Repository) -> some View {
        let dragging = draggingId == repo.id
        RepoSettingsRow(
            repo: repo,
            accounts: viewModel.accounts,
            isDragging: dragging,
            onChangeAccount: { accountId in
                Task { await viewModel.setAccount(repoId: repo.id, accountId: accountId) }
            },
            onRemove: {
                Task { await viewModel.remove(id: repo.id) }
            },
            onDragChange: { translation in
                if draggingId == nil { draggingId = repo.id }
                dragTranslation = translation
                updateDragTarget()
            },
            onDragEnd: { commitDrag() }
        )
        .background(rowHeightReader(idx: idx))
        // No scaleEffect while dragging: scaling a full-width row from its centre
        // shoves the left-edge grip ~10 pt sideways, so it visibly drifts off the
        // cursor. A shadow + zIndex give the "lifted" feel without moving the grip.
        .offset(y: rowOffset(idx: idx, isDragging: dragging))
        .shadow(color: .black.opacity(dragging ? 0.28 : 0),
                radius: dragging ? 12 : 0, y: dragging ? 6 : 0)
        .zIndex(dragging ? 1 : 0)
        // The dragged row follows the finger 1:1 via `dragTranslation`, which
        // this animation deliberately doesn't observe. The other rows spring
        // aside only when the discrete `dragTarget` slot changes — so moving
        // within a slot never restarts the animation, which is what killed the
        // judder.
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: dragTarget)
    }

    // MARK: - Drag-reorder maths

    /// Recomputes the target slot from the live drag translation, with
    /// hysteresis: the dragged row must cross a slot's centre by `margin` before
    /// committing to that slot. Without it, a hand resting near a boundary
    /// flip-flops between two slots and the let-aside rows judder.
    private func updateDragTarget() {
        guard let id = draggingId,
              let from = viewModel.repos.firstIndex(where: { $0.id == id }) else { return }
        let step = rowHeight + 1 // +1 for the hairline separator
        let raw = dragTranslation / step
        let last = viewModel.repos.count - 1
        let margin: CGFloat = 0.2
        var target = dragTarget ?? from
        while target < last, raw > CGFloat(target - from) + 0.5 + margin { target += 1 }
        while target > 0,    raw < CGFloat(target - from) - 0.5 - margin { target -= 1 }
        if target != dragTarget { dragTarget = target }
    }

    /// Vertical offset for a row during a drag: the dragged row follows the
    /// cursor; rows between its origin and target slot shift one slot to fill
    /// the gap; everything else stays put.
    private func rowOffset(idx: Int, isDragging: Bool) -> CGFloat {
        guard let id = draggingId,
              let from = viewModel.repos.firstIndex(where: { $0.id == id }),
              let to = dragTarget else { return 0 }
        if isDragging { return dragTranslation }
        let step = rowHeight + 1
        if from < to, idx > from, idx <= to { return -step }
        if from > to, idx >= to, idx < from { return step }
        return 0
    }

    /// On release: apply the move optimistically and clear the drag state — all
    /// inside one animation so the row springs into place instead of snapping
    /// back then jumping.
    private func commitDrag() {
        let from = draggingId.flatMap { id in viewModel.repos.firstIndex(where: { $0.id == id }) }
        let to = dragTarget
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if let from, let to, to != from {
                // Convert our final index back to move(fromOffsets:toOffset:) space.
                let dest = to >= from ? to + 1 : to
                viewModel.applyReorder(from: from, to: dest)
            }
            draggingId = nil
            dragTranslation = 0
            dragTarget = nil
        }
    }

    /// Measures the first row's height so `targetIndex` can map a drag distance
    /// to a number of slots. Rows are uniform, so one sample suffices.
    private func rowHeightReader(idx: Int) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { if idx == 0 { rowHeight = geo.size.height } }
                // Freeze the measurement mid-drag so an animating layout can't
                // feed a changing rowHeight back into the slot maths.
                .onChange(of: geo.size.height) { _, h in if idx == 0, draggingId == nil { rowHeight = h } }
        }
    }
}

// MARK: - Button styles
//
// `.btn.ghost.sm` and `.btn.amber` from styles.css. Ghost = transparent until
// hover (then glass2 + text1); amber = the primary CTA — a vertical amber
// gradient with dark ink, a top inset highlight, and an amber glow. Both use a
// 9 pt rounded rect (not a capsule) and nudge down 0.5 pt while pressed
// (`.btn:active { transform: translateY(0.5px) }`).

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration) }

    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false

        var body: some View {
            configuration.label
                .aerieFont(AerieFont.small().weight(.medium))
                .foregroundStyle(hover ? AerieColor.text1 : AerieColor.text3)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hover ? AerieColor.glass2 : Color.clear)
                )
                .offset(y: configuration.isPressed ? 0.5 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.18), value: hover)
        }
    }
}

private struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration) }

    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false

        var body: some View {
            configuration.label
                .aerieFont(AerieFont.custom(.sans, size: 13).weight(.semibold))
                .foregroundStyle(AerieColor.amberInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AerieColor.amberFillTop, AerieColor.amberFillBot],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(AerieColor.amberCtaLine, lineWidth: 1)
                )
                // inset 0 1px 0 0 oklch(1 0 0 / 0.40) — bright top edge.
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.40), Color.clear],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.plusLighter)
                )
                .shadow(color: AerieColor.amberGlow, radius: 5, y: 2)
                .brightness(hover ? 0.04 : 0) // filter: brightness(1.05)
                .offset(y: configuration.isPressed ? 0.5 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.18), value: hover)
        }
    }
}
