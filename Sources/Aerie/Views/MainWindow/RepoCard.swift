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
/// - Footer: failure / merged-branch strips, then the worktree rail.
///
/// Below regular width the card follows `compact.jsx` `CompactRepoRow`: name
/// and a `⋯` menu holding every action, then the branch chip with its tags and
/// ahead/behind counts (one line at medium, two at compact). The worktree rail
/// collapses to an "N worktrees" tag; the status strips still show below.
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

    @Environment(\.widthClass) private var widthClass

    var body: some View {
        switch widthClass {
        case .regular:
            regularCard
        case .medium, .compact:
            adaptiveRow
        }
    }

    private var regularCard: some View {
        VStack(alignment: .leading, spacing: 0) {
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

    private var showsStatusStrips: Bool {
        resetFailure != nil || discardFailure != nil || (row.mergedBranch != nil && !isResetting)
    }

    private var showsFooter: Bool {
        !row.worktrees.isEmpty || showsStatusStrips
    }

    @ViewBuilder
    private var footer: some View {
        if showsFooter {
            VStack(alignment: .leading, spacing: 8) {
                statusStrips
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

    /// Failure / merged-hint strips — shown at every width.
    @ViewBuilder
    private var statusStrips: some View {
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
    }

    // MARK: - Medium / compact row

    private var adaptiveRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            if widthClass == .medium {
                HStack(spacing: 11) {
                    StatusDot(tone: adaptiveDotTone)
                    nameLabel
                    branchLine
                    runningSpinner
                    overflowMenu
                }
            } else {
                HStack(spacing: 9) {
                    StatusDot(tone: adaptiveDotTone)
                    nameLabel
                    Spacer(minLength: 8)
                    runningSpinner
                    overflowMenu
                }
                branchLine
                    .padding(.top, 9)
            }
            if showsStatusStrips {
                VStack(alignment: .leading, spacing: 8) {
                    statusStrips
                }
                .padding(.top, 10)
            }
        }
        .adaptiveRowPlate(widthClass)
        .popover(isPresented: $showResetConfirm) { resetDialog }
        .background(Color.clear.popover(isPresented: $showDiscardConfirm) { discardDialog })
    }

    /// `CompactRepoRow` dot: crimson when the tree is dirty, green otherwise.
    private var adaptiveDotTone: StatusPill.Tone {
        row.status?.isDirty == true ? .err : .ok
    }

    private var nameLabel: some View {
        Text(repoTitle)
            .aerieFont(AerieFont.custom(.sans, size: 14).weight(.semibold))
            .foregroundStyle(AerieColor.text1)
            .lineLimit(1)
            .layoutPriority(1)
    }

    /// Branch chip · tags · (spacer) · ↓behind ↑ahead · N worktrees.
    private var branchLine: some View {
        HStack(spacing: 8) {
            Text(branchName)
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text1)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: AerieMetric.radiusPill).fill(AerieColor.glass2))
                .overlay(RoundedRectangle(cornerRadius: AerieMetric.radiusPill).strokeBorder(AerieColor.glassLine, lineWidth: 1))
            if let merged = row.mergedBranch {
                MiniPill(text: isResetting ? "resetting" : "merged · #\(merged.prNumber)",
                         tone: isResetting ? .arc : .amber)
            } else if !isOnDefault {
                MiniPill(text: "off default", tone: .amber)
            }
            if row.repo.apiSyncDisabled { MiniPill(text: "sync paused", tone: .muted) }
            if row.status?.isDirty == true { MiniPill(text: "dirty", tone: .err) }
            Spacer(minLength: 8)
            AheadBehindCounts(ahead: row.status?.aheadOfDefault ?? 0,
                              behind: row.status?.behindOfDefault ?? 0)
            if !row.worktrees.isEmpty {
                MiniPill(text: "\(row.worktrees.count) worktree\(row.worktrees.count == 1 ? "" : "s")",
                         tone: .muted)
                    .help("Widen the window to manage worktrees")
            }
        }
    }

    @ViewBuilder
    private var runningSpinner: some View {
        if isResetting || isDiscarding {
            CardArcSpinner(size: 11)
        }
    }

    /// Every action the regular card shows inline, plus Remove (its corner ×).
    private var overflowMenu: some View {
        RowOverflowMenu(help: "Actions for \(repoTitle)") {
            Button("Open in Finder", action: onOpen)
            Divider()
            if Self.shouldShowDiscard(row.status) {
                Button(isDiscarding ? "Discarding…" : "Discard All Unstaged…") { showDiscardConfirm = true }
                    .disabled(isDiscarding)
            }
            Button(isResetting ? "Resetting…" : Self.resetTitle(row) + "…") { showResetConfirm = true }
                .disabled(row.status == nil || isResetting)
            Divider()
            Button(Self.apiSyncToggleHelp(row), action: onToggleApiSync)
            Divider()
            Button("Remove from Aerie", action: onRemove)
        }
    }

    @ViewBuilder
    private var resetDialog: some View {
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

    @ViewBuilder
    private var discardDialog: some View {
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

    // The trailing action cluster: the uniform Open ↗ / Reset row stays on top
    // so those line up across cards; the conditional second row holds the
    // quieter dirty-only Discard.
    private var actionCluster: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                actionButtons
            }
            if Self.shouldShowDiscard(row.status) {
                HStack(spacing: 8) {
                    secondaryActionButtons
                }
            }
        }
    }

    /// Pause/resume toggle + Open ↗ + Reset — the always-present trio.
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
        .popover(isPresented: $showResetConfirm) { resetDialog }
    }

    /// Idle: `resetTitle`. Running: the merged-branch cleanup keeps its label
    /// with a trailing ellipsis (`system.jsx`), a plain reset reads "Resetting…".
    private var resetButtonTitle: String {
        guard isResetting else { return Self.resetTitle(row) }
        return row.mergedBranch != nil ? "Reset & delete branch…" : "Resetting…"
    }

    @ViewBuilder
    private var secondaryActionButtons: some View {
        if Self.shouldShowDiscard(row.status) {
            DiscardButton(isRunning: isDiscarding, action: { if !isDiscarding { showDiscardConfirm = true } })
                .popover(isPresented: $showDiscardConfirm) { discardDialog }
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
}

// MARK: - Footer strips + meta tags

/// A radius-2 status strip in the repo card footer (merged hint): 9×12 padding, tone wash + 1px tone border, row gap 10.
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
