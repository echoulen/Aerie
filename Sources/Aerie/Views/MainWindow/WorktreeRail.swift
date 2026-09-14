import SwiftUI

/// Variant A · left rail — the worktree sub-section nested inside a repo card.
/// Renders as `RepoCard`'s footer: a full-bleed divider, an "N attached
/// worktrees" eyebrow, then a gold-railed list of `WorktreeRowView`s.
struct WorktreeRail: View {
    let worktrees: [WorktreeRow]
    let repo: Repository
    let defaultBranch: String
    var repoActionStore: RepoActionStore = RepoActionStore()
    /// Returns nil on success, or an error message on failure. Async so the
    /// row's Merge state machine can show idle → Merging… → Up to date / Retry.
    var onMerge: (WorktreeRow) async -> String?
    var onDiscardConfirmed: (WorktreeRow) async -> String? = { _ in nil }
    var onDeleteConfirmed: (WorktreeRow) async -> String? = { _ in nil }

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

            // Gold rail + row-blocks (divider between blocks, so a row's
            // conflict strip stays grouped with its row).
            VStack(spacing: 0) {
                ForEach(Array(worktrees.enumerated()), id: \.element.id) { index, wt in
                    if index > 0 {
                        Rectangle().fill(AerieColor.glassLine).frame(height: 1)
                    }
                    WorktreeRowView(
                        worktree: wt,
                        repo: repo,
                        defaultBranch: defaultBranch,
                        repoActionStore: repoActionStore,
                        onMerge: { await onMerge(wt) },
                        onDiscardConfirmed: onDiscardConfirmed,
                        onDeleteConfirmed: onDeleteConfirmed)
                }
            }
            .padding(.leading, 22)
            .overlay(alignment: .leading) {
                // Gold rail with a faint emitted glow (MARK III hairlines read as lit).
                Rectangle().fill(AerieColor.amberLine).frame(width: 1)
                    .shadow(color: AerieColor.amberGlow.opacity(0.35), radius: 3)
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
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .fill(AerieColor.glass2))
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .strokeBorder(
                    AerieColor.glassLine,
                    style: StrokeStyle(lineWidth: 1, dash: worktree.isDetached ? [3, 2] : [])))
        .fixedSize()
    }
}

// MARK: - Status

/// Dirty → warn `StatusPill` "dirty · N files"; clean → quiet "clean"; prunable
/// → dashed err pill "missing on disk"; locked stacks alongside as its own pill
/// since a worktree can be both dirty and locked at once.
private struct WorktreeStatusView: View {
    let worktree: WorktreeRow

    var body: some View {
        HStack(spacing: 6) {
            if worktree.isLocked {
                Text("locked".uppercased())
                    .aerieFont(AerieFont.custom(.sans, size: 10.5).weight(.semibold))
                    .tracking(1.05)
                    .foregroundStyle(AerieColor.warn)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                            .strokeBorder(AerieColor.warn.opacity(0.36), lineWidth: 1))
                    .fixedSize()
                    .help(worktree.lockReason ?? "This worktree is locked (git worktree lock)")
            }
            dirtinessView
        }
    }

    @ViewBuilder
    private var dirtinessView: some View {
        if worktree.prunable {
            Text("missing on disk".uppercased())
                .aerieFont(AerieFont.custom(.sans, size: 10.5).weight(.semibold))
                .tracking(1.05)
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
                        RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
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
    let repo: Repository
    let defaultBranch: String
    var repoActionStore: RepoActionStore = RepoActionStore()
    var onMerge: () async -> String?
    var onDiscardConfirmed: (WorktreeRow) async -> String? = { _ in nil }
    var onDeleteConfirmed: (WorktreeRow) async -> String? = { _ in nil }

    /// Drives the merge button's idle → Merging… → Up to date (auto-resets)
    /// transition on top of `RepoActionStore`'s idle/running/failed phases —
    /// the store has no "done, briefly" state of its own (`AIReviewStore`
    /// doesn't need one either), so this view adds the transient checkmark
    /// locally.
    @State private var justSucceeded = false
    @State private var showDiscardConfirm = false
    @State private var showDeleteConfirm = false
    @Environment(\.isCompactWidth) private var isCompact

    private var storePhase: ActionPhase { repoActionStore.phase(.mergeWorktree, for: .worktree(worktree)) }

    private var mergeUIPhase: MergeUIPhase {
        if case .running = storePhase { return .running }
        if case .failed = storePhase { return .error }
        return justSucceeded ? .done : .idle
    }

    private var mergeFailureMessage: String? {
        if case .failed(let message) = storePhase { return message }
        return nil
    }

    private var isDiscarding: Bool { repoActionStore.isRunning(.discardWorktree, for: .worktree(worktree)) }

    private var discardFailure: String? {
        if case .failed(let message) = repoActionStore.phase(.discardWorktree, for: .worktree(worktree)) { return message }
        return nil
    }

    private var isDeleting: Bool { repoActionStore.isRunning(.deleteWorktree, for: .worktree(worktree)) }

    private var deleteFailure: String? {
        if case .failed(let message) = repoActionStore.phase(.deleteWorktree, for: .worktree(worktree)) { return message }
        return nil
    }

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
                    mergePhase: mergeUIPhase,
                    isDiscarding: isDiscarding,
                    isDeleting: isDeleting,
                    onMerge: runMerge,
                    onDiscardTapped: { if !isDiscarding { showDiscardConfirm = true } },
                    onDeleteTapped: { if !isDeleting { showDeleteConfirm = true } })
                .popover(isPresented: $showDiscardConfirm) {
                    DialogWorktreeDiscard(
                        repo: repo, worktree: worktree,
                        onConfirm: {
                            showDiscardConfirm = false
                            repoActionStore.start(.discardWorktree, target: .worktree(worktree)) {
                                await onDiscardConfirmed(worktree)
                            }
                        },
                        onCancel: { showDiscardConfirm = false }
                    )
                }
                .popover(isPresented: $showDeleteConfirm) {
                    DialogDeleteWorktree(
                        repo: repo, worktree: worktree,
                        onConfirm: {
                            showDeleteConfirm = false
                            repoActionStore.start(.deleteWorktree, target: .worktree(worktree)) {
                                await onDeleteConfirmed(worktree)
                            }
                        },
                        onCancel: { showDeleteConfirm = false }
                    )
                }
            }
            .padding(.vertical, 11)
            .opacity(worktree.prunable ? 0.5 : 1)

            if let mergeFailureMessage {
                ActionErrorStrip(
                    message: mergeFailureMessage,
                    onRetry: runMerge,
                    onDismiss: { repoActionStore.dismiss(.mergeWorktree, target: .worktree(worktree)) })
            }
            if let discardFailure {
                // Already reads "Discard failed: …" — pass through as-is.
                ActionErrorStrip(
                    message: discardFailure,
                    onRetry: { repoActionStore.retry(.discardWorktree, target: .worktree(worktree)) },
                    onDismiss: { repoActionStore.dismiss(.discardWorktree, target: .worktree(worktree)) })
            }
            if let deleteFailure {
                // Already reads "Delete failed: …" — pass through as-is.
                ActionErrorStrip(
                    message: deleteFailure,
                    onRetry: { repoActionStore.retry(.deleteWorktree, target: .worktree(worktree)) },
                    onDismiss: { repoActionStore.dismiss(.deleteWorktree, target: .worktree(worktree)) })
            }
        }
        .animation(.easeOut(duration: 0.15), value: mergeUIPhase)
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
        guard !repoActionStore.isRunning(.mergeWorktree, for: .worktree(worktree)) else { return }
        justSucceeded = false
        repoActionStore.start(.mergeWorktree, target: .worktree(worktree)) {
            let error = await onMerge()
            if error == nil {
                Task { @MainActor in
                    justSucceeded = true
                    try? await Task.sleep(nanoseconds: 1_900_000_000)
                    justSucceeded = false
                }
            }
            return error
        }
    }
}

/// The Merge button's feedback phases — same 4 states `MergePhase` used to be,
/// now derived from `RepoActionStore` instead of view-local `@State` (so it
/// survives the row being rebuilt, e.g. on a repo-list refresh).
enum MergeUIPhase: Equatable { case idle, running, done, error }

// MARK: - Actions

/// Merge (stateful, everyday) · Discard (dirty only, warns on hover) · separator
/// · Delete (destructive, icon-only, 28×28). No Open — worktrees have no remote.
private struct WorktreeActions: View {
    let worktree: WorktreeRow
    let defaultBranch: String
    let mergePhase: MergeUIPhase
    var isDiscarding: Bool = false
    var isDeleting: Bool = false
    var onMerge: () -> Void
    var onDiscardTapped: () -> Void
    var onDeleteTapped: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            WtMergeButton(defaultBranch: defaultBranch, phase: mergePhase, onTap: onMerge)

            if worktree.isDirty {
                WtActionButton(
                    systemImage: isDiscarding ? "" : "arrow.counterclockwise",
                    title: isDiscarding ? "Discarding…" : "Discard",
                    hoverTone: .danger,
                    isRunning: isDiscarding,
                    action: onDiscardTapped)
                    .disabled(isDiscarding)
                    .help("Discard all unstaged changes in this worktree")
            }

            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 1)

            WtDeleteButton(isRunning: isDeleting, action: onDeleteTapped)
                .disabled(isDeleting)
                .help(isDeleting ? "Deleting worktree…" : "Delete worktree")
        }
        .fixedSize()
    }
}

// MARK: - Merge button (stateless; driven by the row's phase)

/// `.wt-action` with phase-driven feedback. idle (glass key, gold rim on hover)
/// → Merging… (arc-cyan spinner, disabled) → Up to date ✓ (ok-green, disabled)
/// on success; → Retry merge (`is-error`, crimson-tinted, clickable) on conflict. `minWidth` pins the width so the row
/// never jumps between states.
private struct WtMergeButton: View {
    let defaultBranch: String
    let phase: MergeUIPhase
    var onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                icon
                Text(label)
                    .aerieFont(AerieFont.custom(.sans, size: 11.5).weight(.medium))
                    .tracking(0.75)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .frame(minWidth: 172)
            .background(wtKeyShape.fill(fill))
            .overlay(wtKeyShape.strokeBorder(border, lineWidth: 1))
            .shadow(color: glow, radius: glow == .clear ? 0 : 7)
            .contentShape(wtKeyShape)
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
            CardArcSpinner(size: 11)
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
        case .running: return AerieColor.arc
        case .idle:    return hovering ? AerieColor.text1 : AerieColor.text2
        }
    }
    private var fill: Color {
        switch phase {
        case .done:    return AerieColor.ok.opacity(0.12)
        case .error:   return hovering ? AerieColor.dangerFillHover : AerieColor.dangerFill
        case .running: return AerieColor.arcSoft
        case .idle:    return hovering ? AerieColor.glass3 : AerieColor.glass2
        }
    }
    private var border: Color {
        switch phase {
        case .done:    return AerieColor.ok.opacity(0.35)
        case .error:   return hovering ? AerieColor.crimsonHot : AerieColor.dangerLine
        case .running: return AerieColor.arcLine
        case .idle:    return hovering ? AerieColor.amberLine : AerieColor.glassLine
        }
    }
    private var glow: Color {
        switch phase {
        case .running: return AerieColor.arcGlow.opacity(0.30)
        case .idle:    return hovering ? AerieColor.amberGlow.opacity(0.25) : .clear
        case .done, .error: return .clear
        }
    }
}

/// The worktree keys' bevelled geometry (`.wt-action` / `.wt-del`, 6pt cut).
private let wtKeyShape = HudKeyShape(cut: 6)

/// `.wt-action` — labeled bevelled key (used by Discard). `hoverTone: .danger`
/// turns it crimson on hover; `.neutral` lifts to glass3 with a gold rim. Arc
/// cyan with a spinner while running. Presses sink 0.5px.
private struct WtActionButton: View {
    enum HoverTone { case neutral, danger }
    let systemImage: String
    let title: String
    let hoverTone: HoverTone
    var isRunning: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isRunning {
                    CardArcSpinner(size: 11)
                } else {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .aerieFont(AerieFont.custom(.sans, size: 11.5).weight(.medium))
                    .tracking(0.75)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(wtKeyShape.fill(fill))
            .overlay(wtKeyShape.strokeBorder(border, lineWidth: 1))
            .contentShape(wtKeyShape)
        }
        .buttonStyle(WtPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var foreground: Color {
        if isRunning { return AerieColor.arc }
        guard hovering else { return AerieColor.text2 }
        return hoverTone == .danger ? AerieColor.dangerText : AerieColor.text1
    }
    private var fill: Color {
        if isRunning { return AerieColor.arcSoft }
        guard hovering else { return AerieColor.glass2 }
        return hoverTone == .danger ? AerieColor.dangerFill : AerieColor.glass3
    }
    private var border: Color {
        if isRunning { return AerieColor.arcLine }
        guard hovering else { return AerieColor.glassLine }
        return hoverTone == .danger ? AerieColor.dangerLine : AerieColor.amberLine
    }
}

/// `.wt-del` — destructive icon-only bevelled key, 28×28, neutral at rest,
/// crimson (with glow) on hover, arc spinner while deleting, sinks 0.5px on press.
private struct WtDeleteButton: View {
    var isRunning: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if isRunning {
                    CardArcSpinner(size: 13)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(hovering ? AerieColor.dangerText : AerieColor.text4)
                }
            }
                .frame(width: 28, height: 28)
                .background(wtKeyShape.fill(isRunning ? AerieColor.arcSoft : (hovering ? AerieColor.dangerFillHover : Color.clear)))
                .overlay(
                    wtKeyShape.strokeBorder(
                        isRunning ? AerieColor.arcLine : (hovering ? AerieColor.dangerLine : AerieColor.glassLine),
                        lineWidth: 1))
                .shadow(color: hovering && !isRunning ? AerieColor.crimson.opacity(0.35) : .clear, radius: hovering ? 6 : 0)
                .contentShape(wtKeyShape)
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
