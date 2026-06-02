import SwiftUI

/// A single repository row. Renders through the shared ``CardContent`` skeleton,
/// so it stays pixel-consistent with the PR and Issue cards.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `RepoCard(...)`, mapped
/// onto the shared Issue-style layout:
///   ┌──────────────────────────────────────────────────────────────────┐
///   │ <owner> · [off default]                                            │
///   │ <name>                                       [Open ↗] [Reset…]     │
///   │ ⎇ <branch>  ● <status sentence>                                    │
///   └──────────────────────────────────────────────────────────────────┘
/// - Meta: the owner, plus an "off default" pill when the checked-out branch
///   isn't the default.
/// - Title: the repo name.
/// - Chips: the checked-out branch as a ``BranchTag``, then a single
///   tone-coloured ``StatusPill`` summarising the working tree — "Working tree
///   dirty", "Clean · in sync with origin", or an "N ahead · M behind …" line.
/// - Actions: a ghost "Open ↗" and a red `.btn.danger` "Reset to origin/<b>".
struct RepoCard: View {
    let row: RepoRow
    var onOpen: () -> Void
    var onHardReset: () -> Void
    /// Presents the "Discard all unstaged" confirmation. Defaulted to a no-op so
    /// snapshot tests / previews can omit it.
    var onDiscard: () -> Void = {}
    var onMergeWorktree: (WorktreeRow) async -> String? = { _ in nil }
    var onDiscardWorktree: (WorktreeRow) -> Void = { _ in }
    var onDeleteWorktree: (WorktreeRow) -> Void = { _ in }

    // MARK: - Derived presentation bits

    /// Whether the "Discard all unstaged" button shows — only when the working
    /// tree is dirty (there's something unstaged to discard). Static + internal
    /// so it's unit-testable without rendering the view.
    static func shouldShowDiscard(_ status: LocalGitStatus?) -> Bool {
        status?.isDirty == true
    }

    private var repoTitle: String { row.repo.name }
    private var owner: String { row.repo.githubOwner }
    private var defaultBranch: String { row.repo.defaultBranch }

    private var branchName: String {
        row.status?.currentBranch ?? row.repo.defaultBranch
    }

    private var isOnDefault: Bool {
        guard let s = row.status else { return true }
        return s.currentBranch == row.repo.defaultBranch
    }

    /// Mirrors `app.jsx`: clean → ok, dirty → warn, otherwise an
    /// ahead/behind/unpushed summary → amber. `nil` status reads as clean
    /// (we have no evidence to the contrary).
    private var statusTone: StatusPill.Tone {
        guard let s = row.status else { return .ok }
        if s.isDirty { return .warn }
        if s.aheadOfDefault > 0 || s.behindOfDefault > 0 || s.unpushedCommits > 0 { return .amber }
        return .ok
    }

    private var statusText: String {
        guard let s = row.status else { return "Clean · in sync with origin" }
        if s.isDirty { return "Working tree dirty" }
        var bits: [String] = []
        if s.aheadOfDefault > 0  { bits.append("\(s.aheadOfDefault) ahead") }
        if s.behindOfDefault > 0 { bits.append("\(s.behindOfDefault) behind") }
        if s.unpushedCommits > 0 { bits.append("\(s.unpushedCommits) unpushed") }
        return bits.isEmpty ? "Clean · in sync with origin" : bits.joined(separator: " · ")
    }

    // MARK: - Body

    var body: some View {
        CardContent(title: repoTitle) {
            HStack(spacing: 10) {
                Text(owner)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text2)
                if !isOnDefault {
                    MetaDot()
                    offDefaultPill
                }
            }
        } chips: {
            BranchTag(name: branchName, isCurrent: !isOnDefault)
            StatusPill(text: statusText, tone: statusTone, showsDot: true)
        } actions: {
            // Stack vertically: the uniform Open ↗ / Reset row stays on top so
            // those line up across cards; the quieter, dirty-only "Discard all
            // unstaged" sits right-aligned directly below (per the design).
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    CardOpenButton(action: onOpen)
                    DangerButton(title: "Reset to origin/\(defaultBranch)", action: onHardReset)
                }
                if Self.shouldShowDiscard(row.status) {
                    DiscardButton(action: onDiscard)
                }
            }
        } footer: {
            if !row.worktrees.isEmpty {
                WorktreeRail(
                    worktrees: row.worktrees,
                    defaultBranch: row.repo.defaultBranch,
                    onMerge: onMergeWorktree,
                    onDiscard: onDiscardWorktree,
                    onDelete: onDeleteWorktree)
            }
        }
    }

    private var offDefaultPill: some View {
        Text("off default")
            .aerieFont(AerieFont.custom(.sans, size: 10))
            .foregroundStyle(AerieColor.text3)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule(style: .continuous).fill(AerieColor.glass2))
            .overlay(Capsule(style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }
}

// MARK: - Buttons

/// `.btn.danger` — lighter-red text on an `err`-tinted fill with a matching
/// hairline; the fill deepens on hover. 13pt medium sans, 8×14 padding.
private struct DangerButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .aerieFont(AerieFont.custom(.sans, size: 13).weight(.medium))
                .foregroundStyle(AerieColor.dangerText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hovering ? AerieColor.dangerFillHover : AerieColor.dangerFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(AerieColor.dangerLine, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// `.btn.ghost.sm.discard-all-btn` — a quiet ghost button (undo curved-arrow
/// glyph + label) that's the destructive-but-secondary affordance below the
/// Open ↗ / Reset row. Neutral (`text3`) at rest; text + icon turn danger red
/// (`err`) on hover — louder than a normal ghost, quieter than the always-red
/// `Reset to origin/<b>`. Smaller than the primary actions (12pt, 5×10 padding).
private struct DiscardButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text("Discard all unstaged")
                    .aerieFont(AerieFont.custom(.sans, size: 12))
            }
            .foregroundStyle(hovering ? AerieColor.err : AerieColor.text3)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Discard all unstaged changes in the working tree")
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
