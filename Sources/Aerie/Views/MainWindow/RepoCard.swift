import SwiftUI
import AppKit

/// A single repository row on a MARK III `.card` plate.
///
/// Visual contract: `v2/app.jsx` `RepoCard(...)` (+ `worktrees-views.jsx`
/// `WtRepoHead`, `publish.jsx`, `system.jsx`) — a `1.4fr 1fr auto` grid:
///   ┌──────────────────────────────────────────────────────────────────┐
///   │ <owner> · [off default]                                            │
///   │ <name>                    ● <status sentence>   [Open ↗] [Reset…]  │
///   │ ⎇ <branch>                                      [Discard all…]     │
///   └──────────────────────────────────────────────────────────────────┘
/// - Identity: the owner (plus "off default" / "merged · #N" / "API sync
///   paused" tags), the 20pt repo name, and the checked-out branch.
/// - Status: a tone dot + sentence — "Working tree dirty", "Clean · in sync
///   with origin", or an "N ahead · M behind …" line.
/// - Actions: a ghost "Open ↗" and a crimson `.btn.danger` "Reset to
///   origin/<b>", with Create PR / Discard below when relevant.
/// - Footer: failure / publish / merged-branch strips, then the worktree rail.
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
    var onDiscardWorktreeConfirmed: (WorktreeRow) async -> String? = { _ in nil }
    var onDeleteWorktreeConfirmed: (WorktreeRow) async -> String? = { _ in nil }
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

    @Environment(\.isCompactWidth) private var isCompact

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCompact {
                // Narrow window: identity, status and actions stack so the
                // text keeps the full card width.
                VStack(alignment: .leading, spacing: 12) {
                    identityColumn
                    statusLine
                    actionCluster
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Design grid `1.4fr 1fr auto`, column gap 28.
                HStack(alignment: .center, spacing: 28) {
                    identityColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    statusLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                    actionCluster
                        .fixedSize()
                }
            }

            footer
        }
        .padding(.vertical, AerieMetric.cardPaddingV)
        .padding(.horizontal, AerieMetric.cardPaddingH)
        .glass(.card)
        .overlay(alignment: .topTrailing) {
            CardRemoveButton(action: onRemove)
                .padding(.top, 10)
                .padding(.trailing, 12)
        }
    }

    /// Identity column: owner meta row (12pt text-3 + tags) · 20pt name ·
    /// branch glyph + mono branch name.
    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(owner)
                    .aerieFont(AerieFont.custom(.sans, size: 12))
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
                if row.repo.apiSyncDisabled {
                    MetaDot()
                    apiSyncPausedPill
                }
                if let merged = row.mergedBranch {
                    MetaDot()
                    if isResetting {
                        resettingPill
                    } else {
                        mergedPill(merged)
                    }
                } else if !isOnDefault {
                    MetaDot()
                    offDefaultPill
                }
            }

            Text(repoTitle)
                .aerieFont(AerieFont.custom(.sans, size: 20).weight(.medium))
                .tracking(-0.16)
                .foregroundStyle(AerieColor.text1)
                .lineLimit(2)

            HStack(spacing: 8) {
                BranchGlyph()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(AerieColor.text3)
                Text(branchName)
                    .aerieFont(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 2)
        }
    }

    /// Status column: a 7pt tone dot (ok / warn / amber, 8pt glow at 0.6) and
    /// the working-tree sentence in 13.5pt text-2.
    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.6), radius: 4)
            Text(statusText)
                .aerieFont(AerieFont.custom(.sans, size: 13.5))
                .foregroundStyle(AerieColor.text2)
                .lineLimit(2)
        }
    }

    private var statusColor: Color {
        switch statusTone {
        case .warn:  return AerieColor.warn
        case .amber: return AerieColor.amber
        default:     return AerieColor.ok
        }
    }

    private var showsFooter: Bool {
        !row.worktrees.isEmpty || !createFooterIsEmpty || resetFailure != nil
            || discardFailure != nil || (row.mergedBranch != nil && !isResetting)
    }

    @ViewBuilder
    private var footer: some View {
        if showsFooter {
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
                if let merged = row.mergedBranch, !isResetting {
                    mergedHintStrip(merged)
                }
                if !createFooterIsEmpty {
                    createStatusFooter
                }
                if !row.worktrees.isEmpty {
                    WorktreeRail(
                        worktrees: row.worktrees,
                        repo: row.repo,
                        defaultBranch: row.repo.defaultBranch,
                        repoActionStore: repoActionStore,
                        onMerge: onMergeWorktree,
                        onDiscardConfirmed: onDiscardWorktreeConfirmed,
                        onDeleteConfirmed: onDeleteWorktreeConfirmed)
                }
            }
            .padding(.top, 14)
        }
    }

    // The trailing action cluster. Wide: the uniform Open ↗ / Reset row stays
    // on top so those line up across cards; the conditional second row holds
    // the gold Create PR button and the quieter dirty-only Discard. Compact:
    // the same buttons wrap as a flow instead of forcing fixed rows wider than
    // the card. Destructive actions are disabled while claude is running git —
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
            title: resetButtonTitle,
            action: { if !isResetting { showResetConfirm = true } },
            isRunning: isResetting,
            // The merged-branch cleanup is the smaller `.btn.danger.sm`.
            isSmall: row.mergedBranch != nil
        )
        // Blocked (and dimmed by the HUD style) while a publish runs. A running
        // reset stays enabled so its arc key isn't dimmed — the action's
        // `!isResetting` guard already ignores taps.
        .disabled(isCreating && !isResetting)
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

    /// Idle: `resetTitle`. Running: the merged-branch cleanup keeps its label
    /// with a trailing ellipsis (`system.jsx`), a plain reset reads "Resetting…".
    private var resetButtonTitle: String {
        guard isResetting else { return Self.resetTitle(row) }
        return row.mergedBranch != nil ? "Reset & delete branch…" : "Resetting…"
    }

    @ViewBuilder
    private var secondaryActionButtons: some View {
        if Self.shouldShowCreatePR(row) || isCreating {
            CreatePRButton(isCreating: isCreating, action: onCreatePR)
        }
        if Self.shouldShowDiscard(row.status) {
            DiscardButton(isRunning: isDiscarding, action: { if !isDiscarding { showDiscardConfirm = true } })
                .disabled(isCreating || isDiscarding)
                // Only the publish block dims; a running discard shows arc cyan.
                .opacity((isCreating && !isDiscarding) ? 0.45 : 1)
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
        RepoMetaTag(text: "off default")
    }

    /// Grey tag shown when `apiSyncDisabled` is true — the sibling of
    /// `offDefaultPill`, same styling, independent of it (both can show
    /// together).
    private var apiSyncPausedPill: some View {
        RepoMetaTag(text: "API sync paused")
    }

    /// `pill amber` "merged · #N" replacing `off default` when the checked-out
    /// branch is already merged. Opens the merged PR. Gold (not err/ok) reads as
    /// "needs action" without colliding with the danger or clean tones.
    private func mergedPill(_ merged: MergedBranchInfo) -> some View {
        Button {
            NSWorkspace.shared.open(merged.prUrl)
        } label: {
            RepoMetaTag(text: "merged · #\(merged.prNumber)", tone: .amber)
        }
        .buttonStyle(.plain)
        .help("Open merged PR #\(merged.prNumber)")
    }

    /// `pill arc` with a 10pt spinner while the merged-branch cleanup runs.
    private var resettingPill: some View {
        RepoMetaTag(text: "Resetting", tone: .arc, spinner: true)
    }

    /// The merged-branch hint (`system.jsx`): a gold strip explaining why the
    /// card offers "Reset & delete branch".
    private func mergedHintStrip(_ merged: MergedBranchInfo) -> some View {
        RepoFooterStrip(fill: AerieColor.amberSoft, line: AerieColor.amberLine) {
            Text("◈")
                .aerieFont(AerieFont.custom(.sans, size: 12.5))
                .foregroundStyle(AerieColor.amber)
            (Text(merged.branch).font(.custom(AerieFont.mono, size: 12)).foregroundColor(AerieColor.text1)
             + Text(" was merged via #\(merged.prNumber) — reset to origin/\(row.repo.defaultBranch) and delete it"))
                .aerieFont(AerieFont.custom(.sans, size: 12.5))
                .foregroundStyle(AerieColor.text2)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    /// PR-publish status in the card footer (`publish.jsx`): a streaming
    /// `.console` while claude runs, then an ok "Published" strip, a crimson
    /// failure strip with Retry, or a transient "nothing to publish" strip.
    @ViewBuilder
    private var createStatusFooter: some View {
        switch createPhase {
        case .idle:
            EmptyView()
        case .running(let lines):
            CardConsole(lines: lines.isEmpty ? ["Starting claude…"] : lines, maxHeight: 150)
        case .done(let n, let url):
            RepoFooterStrip(fill: AerieColor.ok.opacity(0.10), line: AerieColor.ok.opacity(0.38)) {
                Circle()
                    .fill(AerieColor.ok)
                    .frame(width: 7, height: 7)
                    .shadow(color: AerieColor.ok.opacity(0.85), radius: 5)
                Text("Published")
                    .aerieFont(AerieFont.custom(.sans, size: 12.5))
                    .foregroundStyle(AerieColor.text2)
                    .fixedSize()
                StatusPill(text: "#\(n) opened", tone: .ok)
                Text(url.absoluteString)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Open PR") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.hud(.standard, size: .small))
                    .fixedSize()
                    .help("Open PR #\(n)")
            }
        case .failed(let message):
            RepoFooterStrip(fill: AerieColor.crimsonSoft, line: AerieColor.crimsonLine) {
                Text("⊗")
                    .aerieFont(AerieFont.custom(.sans, size: 13))
                    .foregroundStyle(AerieColor.crimsonHot)
                (Text("Publish failed  ").fontWeight(.bold).foregroundColor(AerieColor.crimsonHot)
                 + Text(message).foregroundColor(AerieColor.text2))
                    .aerieFont(AerieFont.custom(.sans, size: 12.5))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Retry", action: onCreatePR)
                    .buttonStyle(.hud(.danger, size: .small))
                    .fixedSize()
            }
        case .nothingToDo:
            RepoFooterStrip(fill: Color.black.opacity(0.28), line: AerieColor.glassLine) {
                Circle()
                    .fill(AerieColor.text4)
                    .frame(width: 7, height: 7)
                Text("沒有可發佈的變更")
                    .aerieFont(AerieFont.custom(.sans, size: 12.5))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 8)
                HudNote(text: "clears in 4s")
            }
        }
    }
}

// MARK: - Footer strips + meta tags

/// A radius-2 status strip in the repo card footer (publish result, merged
/// hint): 9×12 padding, tone wash + 1px tone border, row gap 10.
private struct RepoFooterStrip<Content: View>: View {
    let fill: Color
    let line: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .strokeBorder(line, lineWidth: 1))
    }
}

/// The small `.pill` used in the repo card's meta row — shrunk to `padding
/// 1px 7px`, `fontSize 10` ("off default", "API sync paused" in text-3; gold
/// "merged · #N"; arc "RESETTING" with a spinner).
private struct RepoMetaTag: View {
    enum Tone { case neutral, amber, arc }
    let text: String
    var tone: Tone = .neutral
    var spinner: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if spinner {
                CardArcSpinner(size: 10, color: foreground)
            }
            Text(text.uppercased())
                .aerieFont(AerieFont.custom(.sans, size: 10).weight(.semibold))
                .tracking(1.0)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .strokeBorder(border, lineWidth: 1))
        .shadow(color: glow, radius: glow == .clear ? 0 : 6)
        .contentShape(Rectangle())
        .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return AerieColor.text3
        case .amber:   return AerieColor.amber
        case .arc:     return AerieColor.arc
        }
    }
    private var fill: Color {
        switch tone {
        case .neutral: return AerieColor.glass2
        case .amber:   return AerieColor.amberSoft
        case .arc:     return AerieColor.arcSoft
        }
    }
    private var border: Color {
        switch tone {
        case .neutral: return AerieColor.glassLine
        case .amber:   return AerieColor.amberLine
        case .arc:     return AerieColor.arcLine
        }
    }
    private var glow: Color {
        switch tone {
        case .neutral: return .clear
        case .amber:   return AerieColor.amberGlow.opacity(0.35)
        case .arc:     return AerieColor.arcGlow.opacity(0.35)
        }
    }
}

// MARK: - Buttons

/// `.btn.danger` — the MARK III crimson bevelled key (crimson-hot text on a
/// crimson wash, brighter rim + glow on hover); `.sm` for the merged-branch
/// cleanup. While the reset runs the key switches to `.btn.arc` with an inline
/// spinner.
private struct DangerButton: View {
    let title: String
    let action: () -> Void
    var isRunning: Bool = false
    var isSmall: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isRunning { CardArcSpinner(size: isSmall ? 10 : 12) }
                Text(title)
            }
        }
        .buttonStyle(.hud(isRunning ? .arc : .danger, size: isSmall ? .small : .regular))
    }
}

/// `.btn.ghost.sm.discard-all-btn` — a quiet ghost bevelled key (undo
/// curved-arrow glyph + label) that's the destructive-but-secondary affordance
/// below the Open ↗ / Reset row. text-3 with a glass hairline at rest; text,
/// rim and wash turn crimson on hover — louder than a normal ghost, quieter
/// than the always-crimson `Reset to origin/<b>`. Arc cyan + spinner while
/// discarding.
private struct DiscardButton: View {
    var isRunning: Bool = false
    let action: () -> Void
    @State private var hovering = false

    private static let shape = HudKeyShape(cut: 6)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isRunning {
                    CardArcSpinner(size: 11)
                } else {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isRunning ? "Discarding…" : "Discard all unstaged")
                    .aerieFont(AerieFont.custom(.sans, size: 11.5).weight(.medium))
                    .tracking(0.69) // 0.06em @ 11.5px
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Self.shape.fill(fill))
            .overlay(Self.shape.strokeBorder(border, lineWidth: 1))
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Discard all unstaged changes in the working tree")
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var lit: Bool { hovering && !isRunning }

    private var foreground: Color {
        if isRunning { return AerieColor.arc }
        return lit ? AerieColor.crimsonHot : AerieColor.text3
    }
    private var fill: Color {
        if isRunning { return AerieColor.arcSoft }
        return lit ? AerieColor.crimsonSoft : .clear
    }
    private var border: Color {
        if isRunning { return AerieColor.arcLine }
        return lit ? AerieColor.crimsonLine : AerieColor.glassLine
    }
}

/// Icon-only ghost toggle that pauses/resumes this repo's GitHub API sync.
/// Mirrors `DiscardButton`'s scale (icon-only, `.plain` style, hover color
/// shift) but swaps to gold when paused so a glance at the card row shows
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

/// The "Create Pull Request" action (`publish.jsx`). Idle: a regular `.btn`
/// bevelled key with gold text on an `amberSoft` wash and `amberLine` rim, so
/// it reads constructive next to the crimson danger key and grey ghosts.
/// Running: a cut-9 arc block (arc text, `arcSoft`, `arcLine` + glow) with a
/// 13pt spinner and "CREATING PR…" — the live console streams below in the
/// card footer.
private struct CreatePRButton: View {
    let isCreating: Bool
    let action: () -> Void

    private static let shape = HudKeyShape(cut: 9)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isCreating {
                    CardArcSpinner(size: 13)
                }
                Text(isCreating ? "CREATING PR…" : "Create Pull Request")
                    .aerieFont(AerieFont.custom(.sans, size: 12.5).weight(isCreating ? .semibold : .medium))
                    .tracking(0.75) // 0.06em @ 12.5px
            }
            .foregroundStyle(isCreating ? AerieColor.arc : AerieColor.amber)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(Self.shape.fill(isCreating ? AerieColor.arcSoft : AerieColor.amberSoft))
            .overlay(Self.shape.strokeBorder(isCreating ? AerieColor.arcLine : AerieColor.amberLine, lineWidth: 1))
            .shadow(color: isCreating ? AerieColor.arcGlow.opacity(0.35) : .clear, radius: isCreating ? 8 : 0)
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
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
