import SwiftUI

/// Variant A · left rail — the worktree sub-section nested inside a repo card.
/// Renders as `RepoCard`'s footer: a full-bleed divider, an "N attached
/// worktrees" eyebrow, then an amber-railed list of `WorktreeRowView`s.
struct WorktreeRail: View {
    let worktrees: [WorktreeRow]
    let defaultBranch: String
    /// Returns nil on success, or an error message on failure. Async so the
    /// row's Merge state machine can show idle → Merging… → Up to date / Retry.
    var onMerge: (WorktreeRow) async -> String?
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

            // Amber rail + row-blocks (divider between blocks, so a row's
            // conflict strip stays grouped with its row).
            VStack(spacing: 0) {
                ForEach(Array(worktrees.enumerated()), id: \.element.id) { index, wt in
                    if index > 0 {
                        Rectangle().fill(AerieColor.glassLine).frame(height: 1)
                    }
                    WorktreeRowView(
                        worktree: wt,
                        defaultBranch: defaultBranch,
                        onMerge: { await onMerge(wt) },
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

/// The Merge button's feedback phases. Owned by `WorktreeRowView` (the row) so
/// a conflict can surface an inline strip below the row — per spec: report the
/// error, leave the worktree unchanged.
private enum MergePhase: Equatable { case idle, running, done, error }

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

// MARK: - Row block (row + optional conflict strip)

/// One worktree row plus, on a merge conflict, an inline error strip below it.
/// Owns the merge state machine: idle → Merging… → Up to date (auto-resets) on
/// success; → Retry merge + conflict strip (stays) on failure. The strip is why
/// the state lives here and not inside the button.
struct WorktreeRowView: View {
    let worktree: WorktreeRow
    let defaultBranch: String
    var onMerge: () async -> String?
    var onDiscard: () -> Void
    var onDelete: () -> Void

    @State private var phase: MergePhase = .idle
    @Environment(\.isCompactWidth) private var isCompact

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact: the fixed-size action cluster (~230pt) drops under the
            // chip row instead of sharing it — side by side they exceed a
            // narrow card's width.
            rowLayout {
                HStack(spacing: 14) {
                    WorktreeBranchChip(worktree: worktree)
                    WorktreeStatusView(worktree: worktree)
                    WorktreePathView(worktree: worktree)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                WorktreeActions(
                    worktree: worktree,
                    defaultBranch: defaultBranch,
                    mergePhase: phase,
                    onMerge: runMerge,
                    onDiscard: onDiscard,
                    onDelete: onDelete)
            }
            .padding(.vertical, 11)
            .opacity(worktree.prunable ? 0.5 : 1)

            if phase == .error {
                ActionErrorStrip(
                    message: "Merge conflict. origin/\(defaultBranch) couldn't be merged cleanly — the merge was aborted and this worktree is unchanged. Resolve it in a terminal, then retry.",
                    onRetry: runMerge,
                    onDismiss: { phase = .idle })
            }
        }
        .animation(.easeOut(duration: 0.15), value: phase)
    }

    /// Wide → one row (chips left, actions right); compact → two stacked rows.
    @ViewBuilder
    private func rowLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 10) { content() }
        } else {
            HStack(spacing: 18) { content() }
        }
    }

    private func runMerge() {
        guard phase != .running else { return }
        phase = .running
        Task {
            let error = await onMerge()
            if error == nil {
                phase = .done
                try? await Task.sleep(nanoseconds: 1_900_000_000)
                if phase == .done { phase = .idle }
            } else {
                // Conflict / failure: hold the Retry state + strip until the
                // user retries or dismisses. The worktree is left unchanged.
                phase = .error
            }
        }
    }
}

// MARK: - Actions

/// Merge (stateful, everyday) · Discard (dirty only, warns on hover) · separator
/// · Delete (destructive, icon-only, 28×28). No Open — worktrees have no remote.
private struct WorktreeActions: View {
    let worktree: WorktreeRow
    let defaultBranch: String
    let mergePhase: MergePhase
    var onMerge: () -> Void
    var onDiscard: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            WtMergeButton(defaultBranch: defaultBranch, phase: mergePhase, onTap: onMerge)

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

// MARK: - Merge button (stateless; driven by the row's phase)

/// `.wt-action` with phase-driven feedback. idle → Merging… (spinner, disabled)
/// → Up to date ✓ (ok-green, disabled) on success; → Retry merge (`is-error`,
/// danger-tinted, clickable) on conflict. `minWidth` pins the width so the row
/// never jumps between states.
private struct WtMergeButton: View {
    let defaultBranch: String
    let phase: MergePhase
    var onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                icon
                Text(label)
                    .aerieFont(AerieFont.custom(.sans, size: 12).weight(.medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .frame(minWidth: 172)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(WtPressStyle())
        .disabled(phase == .running || phase == .done)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: phase)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(helpText)
    }

    @ViewBuilder private var icon: some View {
        switch phase {
        case .running:
            SpinnerView(size: 11).foregroundStyle(AerieColor.text2)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
        case .idle, .error:
            Image(systemName: "arrow.triangle.merge").font(.system(size: 12, weight: .medium))
        }
    }

    private var label: String {
        switch phase {
        case .running: return "Merging…"
        case .done:    return "Up to date"
        case .error:   return "Retry merge"
        case .idle:    return "Merge from origin/\(defaultBranch)"
        }
    }

    private var helpText: String {
        phase == .error
            ? "Try the merge again"
            : "Fetch and merge origin/\(defaultBranch) into this worktree"
    }

    private var foreground: Color {
        switch phase {
        case .done:    return AerieColor.ok
        case .error:   return AerieColor.dangerText
        case .running: return AerieColor.text2
        case .idle:    return hovering ? AerieColor.text1 : AerieColor.text2
        }
    }
    private var fill: Color {
        switch phase {
        case .done:    return AerieColor.ok.opacity(0.12)
        case .error:   return AerieColor.err.opacity(hovering ? 0.22 : 0.14)
        case .running: return AerieColor.glass2
        case .idle:    return hovering ? AerieColor.glass3 : AerieColor.glass2
        }
    }
    private var border: Color {
        switch phase {
        case .done:    return AerieColor.ok.opacity(0.35)
        case .error:   return AerieColor.err.opacity(0.45)
        case .running: return AerieColor.glassLine
        case .idle:    return hovering ? AerieColor.glassLine2 : AerieColor.glassLine
        }
    }
}

/// Ring with a transparent quadrant that spins continuously — the design's
/// `.spinner` (2px stroke, top/right transparent, 0.7s linear infinite). Tint
/// it from the caller with `.foregroundStyle(_:)`.
private struct SpinnerView: View {
    var size: CGFloat = 11
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.6)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

/// `.wt-action` — labeled pill button (used by Discard). `hoverTone: .danger`
/// turns it red on hover; `.neutral` lifts to glass3. Presses sink 0.5px.
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
        .buttonStyle(WtPressStyle())
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

/// `.wt-del` — destructive icon-only button, 28×28, neutral at rest, red on
/// hover, sinks 0.5px on press.
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
        .buttonStyle(WtPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Shared press affordance for the worktree action buttons: the label sinks
/// 0.5px while held (the design's `:active { transform: translateY(0.5px) }`).
private struct WtPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
