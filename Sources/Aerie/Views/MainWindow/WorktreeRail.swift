import SwiftUI

/// Variant A · left rail — the worktree sub-section nested inside a repo card.
/// Renders as `RepoCard`'s footer: a full-bleed divider, an "N attached
/// worktrees" eyebrow, then an amber-railed list of `WorktreeRowView`s.
struct WorktreeRail: View {
    let worktrees: [WorktreeRow]
    var onMerge: (WorktreeRow) -> Void
    var onDiscard: (WorktreeRow) -> Void
    var onDelete: (WorktreeRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full-bleed hairline (design: margin 18px -26px 0). CardContent's
            // horizontal padding is 28, so -28 reaches the card edge.
            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(height: 1)
                .padding(.horizontal, -28)
                .padding(.top, 18)

            // Eyebrow
            HStack(spacing: 8) {
                BranchGlyph()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(AerieColor.text4)
                Text("\(worktrees.count) attached worktree\(worktrees.count == 1 ? "" : "s")")
                    .aerieFont(AerieFont.code(10))
                    .tracking(1.8) // 0.18em at 10px
                    .textCase(.uppercase)
                    .foregroundStyle(AerieColor.text4)
            }
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Amber rail + rows (divider between rows)
            VStack(spacing: 0) {
                ForEach(Array(worktrees.enumerated()), id: \.element.id) { index, wt in
                    if index > 0 {
                        Rectangle().fill(AerieColor.glassLine).frame(height: 1)
                    }
                    WorktreeRowView(
                        worktree: wt,
                        onMerge: { onMerge(wt) },
                        onDiscard: { onDiscard(wt) },
                        onDelete: { onDelete(wt) })
                }
            }
            .padding(.leading, 22)
            .overlay(alignment: .leading) {
                Rectangle().fill(AerieColor.amberLine).frame(width: 1)
            }
            .padding(.leading, 5)
            .padding(.bottom, 2)
        }
    }
}

// MARK: - Branch chip

/// Denser sibling of `BranchTag`: mono branch name, glass chip. Detached gets a
/// dashed border + a quiet "detached" tag and a short SHA in place of a branch.
private struct WorktreeBranchChip: View {
    let worktree: WorktreeRow

    var body: some View {
        HStack(spacing: 7) {
            BranchGlyph()
                .frame(width: 11, height: 11)
                .foregroundStyle(AerieColor.text2.opacity(0.75))
            Text(worktree.branchLabel)
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(worktree.isDetached ? AerieColor.text2 : AerieColor.text1)
            if worktree.isDetached {
                Text("detached")
                    .aerieFont(AerieFont.custom(.sans, size: 10.5))
                    .tracking(0.42)
                    .foregroundStyle(AerieColor.text4)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AerieColor.glass2))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    AerieColor.glassLine,
                    style: StrokeStyle(lineWidth: 1, dash: worktree.isDetached ? [3, 2] : [])))
        .fixedSize()
    }
}

// MARK: - Status

/// Dirty → warn `StatusPill` "dirty · N files"; clean → quiet "clean"; prunable
/// → dashed err pill "missing on disk".
private struct WorktreeStatusView: View {
    let worktree: WorktreeRow

    var body: some View {
        if worktree.prunable {
            Text("missing on disk")
                .aerieFont(AerieFont.custom(.sans, size: 11).weight(.medium))
                .tracking(0.22)
                .foregroundStyle(AerieColor.err)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                        .strokeBorder(
                            AerieColor.err.opacity(0.36),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .fixedSize()
        } else if worktree.isDirty {
            StatusPill(
                text: "dirty · \(worktree.dirtyFileCount) file\(worktree.dirtyFileCount == 1 ? "" : "s")",
                tone: .warn, showsDot: true)
        } else {
            Text("clean")
                .aerieFont(AerieFont.custom(.sans, size: 12))
                .foregroundStyle(AerieColor.text4)
        }
    }
}

// MARK: - Path + source

/// Faint mono path, preceded by a `superset` source tag (manual shows no tag).
private struct WorktreePathView: View {
    let worktree: WorktreeRow

    var body: some View {
        HStack(spacing: 8) {
            if worktree.source == .superset {
                Text("superset")
                    .aerieFont(AerieFont.code(9.5))
                    .tracking(0.57) // 0.06em at 9.5px
                    .textCase(.uppercase)
                    .foregroundStyle(AerieColor.text3)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(AerieColor.glassLine, lineWidth: 1))
                    .fixedSize()
            }
            Text(worktree.path.path)
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Row

/// One worktree row: `[branch · status · path]` on the left, the action cluster
/// on the right (design grid `minmax(0,1fr) auto`, column-gap 18, padding 11×0).
struct WorktreeRowView: View {
    let worktree: WorktreeRow
    var onMerge: () -> Void
    var onDiscard: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 14) {
                WorktreeBranchChip(worktree: worktree)
                WorktreeStatusView(worktree: worktree)
                WorktreePathView(worktree: worktree)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WorktreeActions(
                worktree: worktree,
                onMerge: onMerge, onDiscard: onDiscard, onDelete: onDelete)
        }
        .padding(.vertical, 11)
        .opacity(worktree.prunable ? 0.5 : 1)
    }
}

// MARK: - Actions

/// Merge (everyday) · Discard (dirty only, warns on hover) · separator ·
/// Delete (destructive, icon-only, 28×28). No Open — worktrees have no remote.
private struct WorktreeActions: View {
    let worktree: WorktreeRow
    var onMerge: () -> Void
    var onDiscard: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            WtActionButton(
                systemImage: "arrow.triangle.merge",
                title: "Merge from origin/main",
                hoverTone: .neutral, action: onMerge)
                .help("Fetch and merge origin/main into this worktree")

            if worktree.isDirty {
                WtActionButton(
                    systemImage: "arrow.counterclockwise",
                    title: "Discard",
                    hoverTone: .danger, action: onDiscard)
                    .help("Discard all unstaged changes in this worktree")
            }

            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 1)

            WtDeleteButton(action: onDelete)
                .help("Delete worktree")
        }
        .fixedSize()
    }
}

/// `.wt-action` — labeled pill button. `hoverTone: .danger` turns it red on
/// hover (the Discard affordance); `.neutral` lifts to glass3 (Merge).
private struct WtActionButton: View {
    enum HoverTone { case neutral, danger }
    let systemImage: String
    let title: String
    let hoverTone: HoverTone
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .medium))
                Text(title).aerieFont(AerieFont.custom(.sans, size: 12).weight(.medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var foreground: Color {
        guard hovering else { return AerieColor.text2 }
        return hoverTone == .danger ? AerieColor.err : AerieColor.text1
    }
    private var fill: Color {
        guard hovering else { return AerieColor.glass2 }
        return hoverTone == .danger ? AerieColor.err.opacity(0.12) : AerieColor.glass3
    }
    private var border: Color {
        guard hovering else { return AerieColor.glassLine }
        return hoverTone == .danger ? AerieColor.err.opacity(0.4) : AerieColor.glassLine2
    }
}

/// `.wt-del` — destructive icon-only button, 28×28, neutral at rest, red on hover.
private struct WtDeleteButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 13))
                .foregroundStyle(hovering ? AerieColor.dangerText : AerieColor.text4)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? AerieColor.err.opacity(0.16) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            hovering ? AerieColor.err.opacity(0.45) : AerieColor.glassLine,
                            lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
