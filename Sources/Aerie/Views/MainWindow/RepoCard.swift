import SwiftUI
import AppKit

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
    /// Background store for Hard-reset/Discard-unstaged. Defaulted so
    /// previews / snapshot tests can omit it.
    var repoActionStore: RepoActionStore = RepoActionStore()
    /// Runs the actual `git reset --hard` (+ merged-branch cleanup). Returns
    /// an error message on failure, nil on success.
    var onHardResetConfirmed: (RepoRow) async -> String? = { _ in nil }
    /// Runs the actual discard-unstaged (`git restore .` + `git clean -fd`).
    /// Returns an error message on failure, nil on success.
    var onDiscardConfirmed: (RepoRow) async -> String? = { _ in nil }
    var onMergeWorktree: (WorktreeRow) async -> String? = { _ in nil }
    var onDiscardWorktree: (WorktreeRow) -> Void = { _ in }
    var onDeleteWorktree: (WorktreeRow) -> Void = { _ in }
    /// The repo's PR-publish phase (from `PRCreateStore`). Defaulted so
    /// previews / snapshot tests can omit it.
    var createPhase: PRCreatePhase = .idle
    /// Starts (or retries) a claude-driven PR publish for this repo.
    var onCreatePR: () -> Void = {}
    /// Pauses or resumes this repo's GitHub API sync (PRs, Issues,
    /// merged-branch check). Local git operations are unaffected either way.
    var onToggleApiSync: () -> Void = {}
    /// Untracks this repo (removes it from Aerie's list; the on-disk clone is
    /// untouched). Defaulted so previews / snapshot tests can omit it.
    var onRemove: () -> Void = {}

    // MARK: - Derived presentation bits

    /// Whether the "Discard all unstaged" button shows — only when the working
    /// tree is dirty (there's something unstaged to discard). Static + internal
    /// so it's unit-testable without rendering the view.
    static func shouldShowDiscard(_ status: LocalGitStatus?) -> Bool {
        status?.isDirty == true
    }

    /// Whether "Create Pull Request" shows — only when there is something to
    /// publish (dirty tree, commits ahead/unpushed, or an off-default branch).
    /// Always hidden once the branch is merged: the right action there is
    /// "Reset & delete branch", not another PR. `nil` status reads as clean.
    static func shouldShowCreatePR(_ row: RepoRow) -> Bool {
        guard row.mergedBranch == nil else { return false }
        guard let s = row.status else { return false }
        let offDefault = s.currentBranch != row.repo.defaultBranch
        return s.isDirty || s.aheadOfDefault > 0 || s.unpushedCommits > 0 || offDefault
    }

    /// The toggle button's SF Symbol name — swaps between "pause" (sync
    /// active, click to pause) and "play" (sync paused, click to resume) so
    /// the icon always reflects `Repository.apiSyncDisabled`. Static +
    /// internal so it's unit-testable without rendering the view.
    static func apiSyncToggleIcon(_ row: RepoRow) -> String {
        row.repo.apiSyncDisabled ? "play.circle" : "pause.circle"
    }

    /// The toggle button's tooltip, mirroring `apiSyncToggleIcon`'s state split.
    static func apiSyncToggleHelp(_ row: RepoRow) -> String {
        row.repo.apiSyncDisabled ? "Resume API sync" : "Pause API sync (PR / Issue)"
    }

    private var isCreating: Bool {
        if case .running = createPhase { return true }
        return false
    }

    private var createFooterIsEmpty: Bool {
        if case .idle = createPhase { return true }
        return false
    }

    private var isResetting: Bool { repoActionStore.isRunning(.hardReset, for: .repo(row.repo)) }

    private var resetFailure: String? {
        if case .failed(let message) = repoActionStore.phase(.hardReset, for: .repo(row.repo)) { return message }
        return nil
    }

    @State private var showResetConfirm = false

    private var isDiscarding: Bool { repoActionStore.isRunning(.discardUnstaged, for: .repo(row.repo)) }

    private var discardFailure: String? {
        if case .failed(let message) = repoActionStore.phase(.discardUnstaged, for: .repo(row.repo)) { return message }
        return nil
    }

    @State private var showDiscardConfirm = false

    /// The danger button's title. When the checked-out branch is already merged,
    /// the action also force-deletes that local branch, so the label says so.
    /// Static + internal so it's unit-testable without rendering the view.
    static func resetTitle(_ row: RepoRow) -> String {
        row.mergedBranch != nil
            ? "Reset & delete branch"
            : "Reset to origin/\(row.repo.defaultBranch)"
    }

    private var repoTitle: String { row.repo.name }
    private var owner: String { row.repo.githubOwner }
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
                if row.repo.apiSyncDisabled {
                    MetaDot()
                    apiSyncPausedPill
                }
                if let merged = row.mergedBranch {
                    MetaDot()
                    mergedPill(merged)
                } else if !isOnDefault {
                    MetaDot()
                    offDefaultPill
                }
            }
        } chips: {
            BranchTag(name: branchName, isCurrent: !isOnDefault)
            StatusPill(text: statusText, tone: statusTone, showsDot: true)
        } actions: {
            actionCluster
        } footer: {
            if !row.worktrees.isEmpty || !createFooterIsEmpty || resetFailure != nil || discardFailure != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let resetFailure {
                        // `resetFailure` already reads "Reset failed: …" (the
                        // `onHardResetConfirmed` closure's error string) — pass
                        // it through as-is, don't add a second prefix.
                        ActionErrorStrip(
                            message: resetFailure,
                            onRetry: { repoActionStore.retry(.hardReset, target: .repo(row.repo)) },
                            onDismiss: { repoActionStore.dismiss(.hardReset, target: .repo(row.repo)) })
                    }
                    if let discardFailure {
                        // Already reads "Discard failed: …" — pass through as-is.
                        ActionErrorStrip(
                            message: discardFailure,
                            onRetry: { repoActionStore.retry(.discardUnstaged, target: .repo(row.repo)) },
                            onDismiss: { repoActionStore.dismiss(.discardUnstaged, target: .repo(row.repo)) })
                    }
                    if !createFooterIsEmpty {
                        createStatusFooter
                    }
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
        }
        .overlay(alignment: .topTrailing) {
            CardRemoveButton(action: onRemove)
                .padding(.top, 10)
                .padding(.trailing, 12)
        }
    }

    @Environment(\.isCompactWidth) private var isCompact

    // The trailing action cluster. Wide: the uniform Open ↗ / Reset row stays
    // on top so those line up across cards; the conditional second row holds
    // the amber Create PR button and the quieter dirty-only Discard. Compact:
    // CardContent puts this slot under the content, so the same buttons wrap
    // as a flow instead of forcing fixed rows wider than the card.
    // Destructive actions are disabled while claude is running git —
    // a hard reset mid-publish would corrupt the flow.
    @ViewBuilder
    private var actionCluster: some View {
        if isCompact {
            FlowLayout(itemSpacing: 8, rowSpacing: 8) {
                actionButtons
            }
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    actionButtons
                }
                if Self.shouldShowCreatePR(row) || isCreating || Self.shouldShowDiscard(row.status) {
                    HStack(spacing: 8) {
                        secondaryActionButtons
                    }
                }
            }
        }
    }

    /// Pause/resume toggle + Open ↗ + Reset — the always-present trio. In
    /// compact mode the flow layout receives these and the secondary buttons
    /// as one flat run.
    @ViewBuilder
    private var actionButtons: some View {
        ApiSyncToggleButton(
            icon: Self.apiSyncToggleIcon(row),
            isDisabled: row.repo.apiSyncDisabled,
            help: Self.apiSyncToggleHelp(row),
            action: onToggleApiSync)
        CardOpenButton(action: onOpen)
        DangerButton(
            title: isResetting ? "Resetting…" : Self.resetTitle(row),
            action: { if !isResetting { showResetConfirm = true } },
            isRunning: isResetting
        )
        .disabled(isCreating || isResetting)
        .opacity((isCreating || isResetting) ? 0.45 : 1)
        .popover(isPresented: $showResetConfirm) {
            if let status = row.status {
                DialogReset(
                    repo: row.repo, status: status,
                    onConfirm: {
                        showResetConfirm = false
                        repoActionStore.start(.hardReset, target: .repo(row.repo)) {
                            await onHardResetConfirmed(row)
                        }
                    },
                    onCancel: { showResetConfirm = false },
                    mergedBranch: row.mergedBranch
                )
            }
        }
        if isCompact {
            secondaryActionButtons
        }
    }

    @ViewBuilder
    private var secondaryActionButtons: some View {
        if Self.shouldShowCreatePR(row) || isCreating {
            CreatePRButton(isCreating: isCreating, action: onCreatePR)
        }
        if Self.shouldShowDiscard(row.status) {
            DiscardButton(isRunning: isDiscarding, action: { if !isDiscarding { showDiscardConfirm = true } })
                .disabled(isCreating || isDiscarding)
                .opacity((isCreating || isDiscarding) ? 0.45 : 1)
                .popover(isPresented: $showDiscardConfirm) {
                    if let status = row.status {
                        DialogDiscard(
                            repo: row.repo, status: status,
                            onConfirm: {
                                showDiscardConfirm = false
                                repoActionStore.start(.discardUnstaged, target: .repo(row.repo)) {
                                    await onDiscardConfirmed(row)
                                }
                            },
                            onCancel: { showDiscardConfirm = false }
                        )
                    }
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

    /// Grey pill shown when `apiSyncDisabled` is true — the sibling of
    /// `offDefaultPill`, same styling, independent of it (both can show
    /// together).
    private var apiSyncPausedPill: some View {
        Text("API sync paused")
            .aerieFont(AerieFont.custom(.sans, size: 10))
            .foregroundStyle(AerieColor.text3)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule(style: .continuous).fill(AerieColor.glass2))
            .overlay(Capsule(style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }

    /// Amber-toned, clickable pill replacing `off default` when the checked-out
    /// branch is already merged. Opens the merged PR. Amber (not err/ok) reads as
    /// "needs action" without colliding with the danger or clean tones.
    private func mergedPill(_ merged: MergedBranchInfo) -> some View {
        Button {
            NSWorkspace.shared.open(merged.prUrl)
        } label: {
            Text("merged · #\(merged.prNumber)")
                .aerieFont(AerieFont.custom(.sans, size: 10))
                .foregroundStyle(AerieColor.amber)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Capsule(style: .continuous).fill(AerieColor.amberSoft))
                .overlay(Capsule(style: .continuous).strokeBorder(AerieColor.amberLine, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Open merged PR #\(merged.prNumber)")
    }

    /// PR-publish status line in the card footer: live progress while running,
    /// a clickable PR pill on success (mergedPill's palette), an error + Retry
    /// on failure, and a transient neutral line for "nothing to publish".
    @ViewBuilder
    private var createStatusFooter: some View {
        switch createPhase {
        case .idle:
            EmptyView()
        case .running(let lines):
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(AerieColor.amber)
                Text(lines.last ?? "Starting claude…")
                    .aerieFont(AerieFont.custom(.sans, size: 12))
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .done(let n, let url):
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Text("PR #\(n) ↗")
                    .aerieFont(AerieFont.custom(.sans, size: 10))
                    .foregroundStyle(AerieColor.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule(style: .continuous).fill(AerieColor.amberSoft))
                    .overlay(Capsule(style: .continuous).strokeBorder(AerieColor.amberLine, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open PR #\(n)")
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message)
                    .aerieFont(AerieFont.custom(.sans, size: 12))
                    .foregroundStyle(AerieColor.err)
                    .lineLimit(2)
                Button("Retry", action: onCreatePR)
                    .buttonStyle(.plain)
                    .aerieFont(AerieFont.custom(.sans, size: 12).weight(.medium))
                    .foregroundStyle(AerieColor.text2)
            }
        case .nothingToDo:
            Text("沒有可發佈的變更")
                .aerieFont(AerieFont.custom(.sans, size: 12))
                .foregroundStyle(AerieColor.text3)
        }
    }
}

// MARK: - Buttons

/// `.btn.danger` — lighter-red text on an `err`-tinted fill with a matching
/// hairline; the fill deepens on hover. 13pt medium sans, 8×14 padding.
private struct DangerButton: View {
    let title: String
    let action: () -> Void
    var isRunning: Bool = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isRunning { ProgressView().controlSize(.small).tint(AerieColor.dangerText) }
                Text(title)
                    .aerieFont(AerieFont.custom(.sans, size: 13).weight(.medium))
            }
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
    var isRunning: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isRunning ? "Discarding…" : "Discard all unstaged")
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

/// Icon-only ghost toggle that pauses/resumes this repo's GitHub API sync.
/// Mirrors `DiscardButton`'s scale (icon-only, `.plain` style, hover color
/// shift) but swaps to amber when paused so a glance at the card row shows
/// whether sync is active.
private struct ApiSyncToggleButton: View {
    let icon: String
    let isDisabled: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isDisabled ? AerieColor.amber : (hovering ? AerieColor.text2 : AerieColor.text4))
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The amber "Create Pull Request" action — amber text on `amberSoft` fill
/// with an `amberLine` hairline (mergedPill's palette at button scale), so it
/// reads constructive next to the red danger button and grey ghosts. Swaps to
/// a spinner + "Creating PR…" while a publish runs.
private struct CreatePRButton: View {
    let isCreating: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isCreating {
                    ProgressView().controlSize(.small).tint(AerieColor.amber)
                }
                Text(isCreating ? "Creating PR…" : "Create Pull Request")
                    .aerieFont(AerieFont.custom(.sans, size: 13).weight(.medium))
            }
            .foregroundStyle(AerieColor.amber)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AerieColor.amberSoft.opacity(hovering && !isCreating ? 0.75 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AerieColor.amberLine, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
        .onHover { hovering = $0 }
        .help("用本地 claude 依 Settings 的 PR 發布模板建立 pull request")
    }
}

/// Plain faint `×` in the card's top-right corner — same visual language as
/// Settings' RemoveButton: text-4 at rest, brightening to text-2 on hover.
/// Click untracks the repo immediately (no confirmation, matching Settings;
/// removal never touches the on-disk clone).
private struct CardRemoveButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? AerieColor.text2 : AerieColor.text4)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Remove from Aerie")
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
