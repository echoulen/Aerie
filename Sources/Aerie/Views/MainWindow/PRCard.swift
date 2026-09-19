import SwiftUI
import AppKit

/// A single PR row. Renders through the shared ``CardContent`` skeleton, so it
/// stays pixel-consistent with the Issue and Repo cards.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `PRCard`:
///   ┌───────────────────────────────────────────────────────────────┐
///   │ <repo> · #N · <author> · [yours] · <updated ago>             │
///   │ <title>                                     [Review][Merge]  │
///   │ <CI pill>  <Review pill>  <Local-state pill>                  │
///   └───────────────────────────────────────────────────────────────┘
///
/// The whole local-branch picture collapses into one calm sentence pill, and
/// `Merge` only lights hot gold when CI passes *and* the PR is approved.
///
/// Below regular width the row follows `compact.jsx` instead: one line at
/// medium (`MediumPRList`), three stacked lines at compact (`CompactPRRow`).
/// Both drop the inline action column for a review key / row tap plus a `⋯`
/// menu holding every action, and keep the failure strips underneath.
struct PRCard: View {
    let row: PRRow
    /// Background store for Merge/Approve. Defaulted so
    /// previews / snapshot tests can omit it.
    var prActionStore: PRActionStore = PRActionStore()
    /// Resolves the GitHub account the merge confirmation should display as
    /// acting. Defaulted to an "unknown" placeholder for previews / snapshot
    /// tests that don't wire a real account lookup.
    var mergeAccount: (PRRow) -> GitHubAccount = { row in
        GitHubAccount(id: row.repo.primaryAccountId, login: "unknown", host: "github.com")
    }
    /// Runs the actual squash-merge (the old `mergeDialog`'s `onConfirm` body,
    /// now owned by the caller and invoked from `PRActionStore.start`).
    /// Returns an error message on failure, nil on success.
    var onMergeConfirmed: (PRRow) async -> String? = { _ in nil }
    /// Opens the code review screen for this PR. Defaulted to a no-op for
    /// snapshot tests and previews.
    var onReview: () -> Void = {}
    /// Current AI-review lifecycle for this PR — drives the row's own "AI
    /// Review" button (idle/running/done/failed). The "Review" button above
    /// stays untouched by it: it only opens the detail screen, so mirroring
    /// the progress there just printed "Reviewing…" twice. Defaulted to
    /// `.idle` for snapshot tests and previews.
    var aiReviewPhase: AIReviewPhase = .idle
    /// Starts an AI review for this PR directly from the list, without
    /// opening the detail screen. Wraps `AIReviewStore.start(row:)`.
    /// Defaulted to a no-op for snapshot tests and previews.
    var onStartAIReview: () -> Void = {}
    /// Stops this PR's running AI review. Wraps `AIReviewStore.stop(row:)`.
    /// Defaulted to a no-op for snapshot tests and previews.
    var onStopAIReview: () -> Void = {}
    /// Clears a failed AI-review phase back to idle (the error strip's
    /// Dismiss control). Wraps `AIReviewStore.dismiss(row:)`. Defaulted to a
    /// no-op for snapshot tests and previews.
    var onDismissAIReview: () -> Void = {}
    /// Runs the base-branch update for this PR's checkout. Awaited by the
    /// status-row "Update branch" pill so it can spin until the row's sync
    /// settles. Defaulted to a no-op for snapshot tests and previews.
    var onUpdateBranch: () async -> Void = {}
    /// Reference "now" for the relative time string. Tests inject a fixed
    /// value to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()

    @State private var showMergeConfirm = false

    // MARK: - Derived presentation bits

    private var mergeable: Bool { Self.isMergeable(row.pr) }

    /// Whether the Merge button should light up. Thin wrapper over
    /// ``PullRequest/mergeBlockReason`` — the single source of truth shared with
    /// the pre-merge re-validation in `MultiAccountAPI.mergePR`, so "button lit"
    /// and "merge allowed" can't drift apart in their logic (only in freshness:
    /// the button reads a cached row, the re-validation a live one).
    /// Static + internal so it's unit-testable without rendering the view.
    static func isMergeable(_ pr: PullRequest) -> Bool {
        pr.isMergeableByGitHub
    }

    private var isMerging: Bool { prActionStore.isRunning(.merge, for: row) }

    private var mergeFailure: String? {
        if case .failed(let message) = prActionStore.phase(.merge, for: row) { return message }
        return nil
    }

    private var isAIReviewing: Bool { if case .running = aiReviewPhase { return true }; return false }

    private var aiReviewFailure: String? {
        if case .failed(let message) = aiReviewPhase { return message }
        return nil
    }

    /// Whether the amber "Update branch" pill should show for this row. Two
    /// independent signals, either of which is enough:
    ///   * the checked-out branch is behind its base (`local.behind > 0`) — the
    ///     local-git view, only available when the PR's branch is the current
    ///     checkout; or
    ///   * GitHub reports the PR as `BEHIND` (`pr.isBehindBase`) — the
    ///     authoritative server view, available even when the branch isn't
    ///     checked out locally, which is exactly the case the local signal
    ///     misses (PR #797: "Not checked out locally", yet GitHub blocks the
    ///     merge until the branch is updated).
    /// Static + internal so it's unit-testable without rendering the view.
    static func shouldShowUpdateBranch(_ pr: PullRequest, _ local: PRLocalState?) -> Bool {
        (local?.behind ?? 0) > 0 || pr.isBehindBase
    }

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
        CardContent(title: row.pr.title, updatedAt: row.pr.updatedAt, now: now) {
            CardMeta(
                name: row.repo.name,
                number: row.pr.number,
                author: row.pr.authorLogin,
                badge: row.pr.isMine ? "yours" : nil
            )
        } chips: {
            // Draft leads the chips: it's the signal that decides whether this
            // PR is even ready to be looked at (and why AI Review is held back).
            if row.pr.isDraftPR {
                StatusPill(text: "Draft", tone: .muted)
            }
            CIChip(state: row.pr.ciState)
            ReviewChip(state: row.pr.reviewState)
            // Someone answered the changes request (a reply or a new commit):
            // AI Review re-runs with those replies in context.
            if row.pr.awaitingReReview {
                StatusPill(text: "Responded · re-review", tone: .amber)
            }
            // Merge conflicts have no chip of their own otherwise — they'd show
            // only as a dimmed Merge button. Surface them explicitly, in red, so
            // the blocking reason is legible at a glance (grouped with the other
            // "can this merge?" signals, before the local-state sentence).
            if row.pr.hasMergeConflicts {
                StatusPill(text: "Conflicts", tone: .err)
            }
            StatusPill(text: localStatus.text, tone: localStatus.tone)
            // Behind its base → offer a one-click update, glued right after the
            // sync chip (never the actions column). `behind` is the local count
            // when checked out, nil when GitHub's the only one reporting BEHIND
            // (not checked out) — the button copes with an unknown count.
            if Self.shouldShowUpdateBranch(row.pr, row.localState) {
                UpdateBranchButton(
                    behind: row.localState?.behind,
                    onUpdate: onUpdateBranch
                )
            }
        } actions: {
            actionColumn
        } footer: {
            failureStrips
        }
    }

    private var hasFailures: Bool {
        mergeFailure != nil || aiReviewFailure != nil
    }

    private var failureStrips: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The merge failure string is already fully-formed ("Merge
            // failed: …") — pass it through as-is.
            if let mergeFailure {
                ActionErrorStrip(
                    message: mergeFailure,
                    onRetry: { prActionStore.retry(.merge, row: row) },
                    onDismiss: { prActionStore.dismiss(.merge, row: row) })
            }
            if let aiReviewFailure {
                ActionErrorStrip(
                    message: aiReviewFailure,
                    onRetry: onStartAIReview,
                    onDismiss: onDismissAIReview)
            }
        }
    }

    // MARK: - Medium / compact row

    private var adaptiveRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            if widthClass == .medium {
                mediumLine
            } else {
                compactLines
            }
            if hasFailures {
                failureStrips
                    .padding(.top, 10)
            }
        }
        .adaptiveRowPlate(widthClass)
        .popover(isPresented: $showMergeConfirm) { mergeDialog }
    }

    /// `MediumPRRow` — two lines that keep the regular card's telemetry:
    ///   1. CI dot · repo · #N · YOURS/DRAFT · title (truncates) · updated
    ///   2. branch chip · CI + review pills · +/− · LOCAL/DIRTY · ↓↑ ·
    ///      [Update] [AI Review] ⋯
    /// The ⋯ menu keeps Merge, AI Review and Copy Link reachable — the actions
    /// the row has no key for.
    private var mediumLine: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                StatusDot(tone: ciTone)
                (Text(row.repo.name) + Text(" · ").foregroundColor(AerieColor.text4) + Text("#\(row.pr.number)"))
                    .aerieFont(AerieFont.code(11))
                    .tracking(0.66)                        // 0.06em @ 11pt
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
                    .fixedSize()
                if row.pr.isMine { MiniPill(text: "yours", tone: .amber) }
                Text(row.pr.title)
                    .aerieFont(AerieFont.custom(.sans, size: 14))
                    .foregroundStyle(AerieColor.text1)
                    .lineLimit(1)
                Spacer(minLength: 10)
                Text(CardRelativeTime.label(for: row.pr.updatedAt, now: now))
                    .aerieFont(AerieFont.code(10.5))
                    .foregroundStyle(AerieColor.text4)
                    .fixedSize()
            }
            // Line 2 carries the same PR information as the regular card.
            // When it doesn't fit, the chips wrap onto another row — nothing
            // is dropped — and the keys stay pinned on the right.
            HStack(alignment: .center, spacing: 10) {
                FlowLayout(itemSpacing: 8, rowSpacing: 6) {
                    mediumBranchChip
                    prInfoChips
                    if let add = row.pr.additions, let del = row.pr.deletions {
                        HStack(spacing: 4) {
                            Text("+\(add)").foregroundStyle(AerieColor.ok)
                            Text("−\(del)").foregroundStyle(AerieColor.crimsonHot)
                        }
                        .aerieFont(AerieFont.code(10.5))
                        .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                mediumActions
            }
        }
    }

    /// The branch in a `.wt-branch` chip; truncates (middle) when a long name
    /// would be wider than the row.
    private var mediumBranchChip: some View {
        Text(row.pr.sourceBranch)
            .aerieFont(AerieFont.code(11))
            .foregroundStyle(AerieColor.text1)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: AerieMetric.radiusPill).fill(AerieColor.glass2))
            .overlay(RoundedRectangle(cornerRadius: AerieMetric.radiusPill).strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }

    /// Narrow rows keep one primary key — AI Review — plus Update when the
    /// branch is behind. Review, Merge and the rest live in the ⋯ menu.
    private var mediumActions: some View {
        HStack(spacing: 7) {
            runningSpinner
            if Self.shouldShowUpdateBranch(row.pr, row.localState) {
                UpdateBranchButton(behind: row.localState?.behind, onUpdate: onUpdateBranch, label: "Update")
            }
            narrowAIReviewKey
            overflowMenu
        }
        .fixedSize()
    }

    /// The narrow rows' primary key: gold `.btn.amber.sm` "AI Review", arc
    /// cyan with a spinner while the review runs — tapping it then stops the
    /// review — disabled on drafts.
    private var narrowAIReviewKey: some View {
        Button(action: aiReviewKeyTapped) {
            HStack(spacing: 6) {
                aiReviewIcon
                Text(aiReviewLabel)
            }
        }
        .buttonStyle(.hud(isAIReviewing ? .arc : .amber, size: .small))
        .disabled(row.pr.isDraftPR && !isAIReviewing)
        .help(aiReviewHelp(verb: "Run AI Review for"))
    }

    /// "CI PASS" / "CI FAIL" / "CI ···".
    private var ciShortLabel: String {
        switch row.pr.ciState {
        case .success: return "CI pass"
        case .failure: return "CI fail"
        case .pending: return "CI ···"
        case .none:    return "No CI"
        }
    }

    private var reviewShortLabel: String {
        switch row.pr.reviewState {
        case .approved:         return "approved"
        case .changesRequested: return row.pr.awaitingReReview ? "responded · re-review" : "changes requested"
        case .reviewRequired:   return "review requested"
        }
    }

    /// `CompactPRRow`: meta line · wrapped title · branch + local state.
    private var compactLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StatusDot(tone: ciTone)
                Text("\(row.repo.name) · #\(row.pr.number)")
                    .aerieFont(AerieFont.code(10.5))
                    .tracking(0.84)                       // 0.08em @ 10.5pt
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
                if row.pr.isMine { MiniPill(text: "yours", tone: .amber) }
                Spacer(minLength: 4)
                Text(CardRelativeTime.label(for: row.pr.updatedAt, now: now))
                    .aerieFont(AerieFont.code(10.5))
                    .foregroundStyle(AerieColor.text4)
                    .fixedSize()
                HStack(spacing: 8) {
                    runningSpinner
                    narrowAIReviewKey
                    overflowMenu
                }
            }
            Text(row.pr.title)
                .aerieFont(AerieFont.custom(.sans, size: 13.5))
                .lineSpacing(4)                            // lh 1.45
                .foregroundStyle(AerieColor.text1)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            Text(row.pr.sourceBranch)
                .aerieFont(AerieFont.code(10.5))
                .foregroundStyle(AerieColor.text3)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 9)
            // Same PR information as the regular card, wrapping as needed.
            FlowLayout(itemSpacing: 6, rowSpacing: 6) {
                prInfoChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 7)
        }
    }

    private var ciTone: StatusPill.Tone {
        switch row.pr.ciState {
        case .success: return .ok
        case .failure: return .err
        case .pending: return .warn
        case .none:    return .muted
        }
    }

    /// The regular card's status chips in the narrow rows' dense form, in the
    /// same order: Draft · CI · Review · Conflicts · local state. Local state
    /// mirrors the regular sentence pill: not checked out / LOCAL + DIRTY /
    /// LOCAL + ahead · behind · unpushed / LOCAL + IN SYNC.
    @ViewBuilder
    private var prInfoChips: some View {
        if row.pr.isDraftPR { MiniPill(text: "draft", tone: .muted) }
        MiniPill(text: ciShortLabel, tone: ciTone)
        MiniPill(text: reviewShortLabel, tone: reviewTone)
        if row.pr.hasMergeConflicts { MiniPill(text: "conflicts", tone: .err) }
        if let local = row.localState, local.isCurrentBranch {
            let ahead = local.ahead ?? 0, behind = local.behind ?? 0, unpushed = local.unpushed ?? 0
            MiniPill(text: "local", tone: .amber)
            if local.dirty == true {
                MiniPill(text: "dirty", tone: .warn)
            } else if ahead == 0 && behind == 0 && unpushed == 0 {
                MiniPill(text: "in sync", tone: .ok)
            }
            if ahead > 0 || behind > 0 {
                AheadBehindCounts(ahead: ahead, behind: behind)
            }
            if unpushed > 0 {
                Text("\(unpushed) unpushed")
                    .aerieFont(AerieFont.code(10.5))
                    .foregroundStyle(AerieColor.amber)
                    .fixedSize()
            }
        } else {
            MiniPill(text: "not checked out", tone: .muted)
        }
    }

    private var reviewTone: StatusPill.Tone {
        switch row.pr.reviewState {
        case .approved:         return .ok
        case .changesRequested: return .err
        case .reviewRequired:   return .neutral
        }
    }

    @ViewBuilder
    private var runningSpinner: some View {
        // Merge runs from the ⋯ menu, so the row shows it's in flight here;
        // AI Review shows its own state on its key.
        if isMerging {
            CardArcSpinner(size: 11)
        }
    }

    /// Every action the regular card shows inline.
    private var overflowMenu: some View {
        RowOverflowMenu(help: "Actions for \(row.repo.name) #\(row.pr.number)") {
            Button("Review Diff", action: onReview)
            if isAIReviewing {
                Button("Stop AI Review", action: onStopAIReview)
            } else {
                Button(aiReviewMenuLabel, action: onStartAIReview)
                    .disabled(row.pr.isDraftPR)
            }
            Divider()
            Button(isMerging ? "Merging…" : "Merge…") { showMergeConfirm = true }
                .disabled(!mergeable || isMerging)
            if Self.shouldShowUpdateBranch(row.pr, row.localState) {
                Button("Update Branch") { Task { await onUpdateBranch() } }
            }
            Divider()
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.pr.htmlUrl.absoluteString, forType: .string)
            }
        }
    }

    private var aiReviewMenuLabel: String {
        if case .failed = aiReviewPhase { return "Retry AI Review" }
        return "AI Review"
    }

    private var mergeDialog: some View {
        DialogMerge(
            pr: row.pr, repo: row.repo, account: mergeAccount(row),
            onConfirm: {
                showMergeConfirm = false
                prActionStore.start(.merge, row: row) { await onMergeConfirmed(row) }
            },
            onCancel: { showMergeConfirm = false }
        )
    }

    // MARK: - Actions column
    //
    // Review · AI Review · Merge stacked top→bottom, equal width and centred —
    // the design's `PRCard` right column (`v2/app.jsx`: "actions, stacked top →
    // bottom"). All are MARK III `.btn.sm` bevelled keys (`HudButtonStyle`). A
    // fixed column width keeps them equal and the cards' action columns aligned
    // down the list. Review shares its top row with a small ``CopyLinkButton``.

    private static let actionColumnWidth: CGFloat = 132

    private var actionColumn: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                reviewButton
                CopyLinkButton(url: row.pr.htmlUrl)
            }
            aiReviewButton
            mergeButton
        }
        .frame(width: Self.actionColumnWidth)
    }

    // MARK III `.btn.sm` key (glass chrome, gold rim on hover) that drills into
    // the code review screen — the in-app "read the diff → approve" entry point.
    private var reviewButton: some View {
        Button(action: onReview) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("Review")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.hud(.standard, size: .small))
        .help("Review the diff for \(row.repo.name) #\(row.pr.number)")
    }

    // Sparkles-icon `.btn.sm` that runs Claude AI Review directly from the
    // list — starts `AIReviewStore.start(row:)` without navigating to the
    // detail screen first. Mirrors the detail screen's `AIReviewButton`
    // (`PRReviewScreen.swift`) but degrades to a plain tap (no account picker)
    // since the row has no room for one; switching accounts still works from
    // the detail screen's split button. While the review runs the key turns
    // arc cyan (`.btn.arc`) — a live process — and reads "Stop": tapping it
    // stops the review.
    private var aiReviewButton: some View {
        Button(action: aiReviewKeyTapped) {
            HStack(spacing: 6) {
                aiReviewIcon
                Text(aiReviewLabel)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.hud(isAIReviewing ? .arc : .standard, size: .small))
        // Running stays enabled — the key is the Stop control then; drafts are
        // truly disabled.
        .disabled(row.pr.isDraftPR && !isAIReviewing)
        .help(aiReviewHelp(verb: "Run AI Review for", suffix: " without opening the diff"))
    }

    /// Both AI Review keys: start when idle, stop while running.
    private func aiReviewKeyTapped() {
        if isAIReviewing { onStopAIReview(); return }
        guard !row.pr.isDraftPR else { return }
        onStartAIReview()
    }

    private func aiReviewHelp(verb: String, suffix: String = "") -> String {
        if isAIReviewing { return "Stop the running AI Review for \(row.repo.name) #\(row.pr.number)" }
        if row.pr.isDraftPR {
            return "\(row.repo.name) #\(row.pr.number) is still a draft — mark it ready for review first"
        }
        return "\(verb) \(row.repo.name) #\(row.pr.number)\(suffix)"
    }

    @ViewBuilder
    private var aiReviewIcon: some View {
        switch aiReviewPhase {
        case .running:
            CardArcSpinner(size: 10)
        case .done(let review, _):
            Image(systemName: review.verdict == .approve ? "checkmark" : "exclamationmark.triangle")
                .font(.system(size: 10, weight: .semibold))
        case .failed:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
        case .idle:
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
        }
    }

    private var aiReviewLabel: String {
        switch aiReviewPhase {
        case .idle: return "AI Review"
        case .running: return "Stop"
        case .done(let review, _): return review.verdict == .approve ? "Approved" : "Issues found"
        case .failed: return "Retry AI Review"
        }
    }

    // MARK: - Local state → one sentence pill

    /// Mirrors the design's `localState` branch in `app.jsx`: a single tone +
    /// sentence describing whether this PR's branch is checked out and in sync.
    private var localStatus: (tone: StatusPill.Tone, text: String) {
        guard let local = row.localState, local.isCurrentBranch else {
            return (.muted, "Not checked out locally")
        }
        if local.dirty == true {
            return (.warn, "Branch checked out · working tree dirty")
        }
        let ahead = local.ahead ?? 0
        let behind = local.behind ?? 0
        let unpushed = local.unpushed ?? 0
        if ahead > 0 || behind > 0 || unpushed > 0 {
            var bits: [String] = []
            if ahead > 0 { bits.append("\(ahead) ahead") }
            if behind > 0 { bits.append("\(behind) behind") }
            if unpushed > 0 { bits.append("\(unpushed) unpushed") }
            return (.amber, "Branch checked out · " + bits.joined(separator: " · "))
        }
        return (.ok, "Branch checked out · clean & in sync")
    }

    // MARK: - Merge button

    /// `.btn.amber.sm` (hot-gold gradient CTA) when mergeable, a dimmed glass
    /// key otherwise, and an arc-cyan running key while the merge is in flight.
    private var mergeButton: some View {
        Button {
            guard !isMerging else { return }
            showMergeConfirm = true
        } label: {
            HStack(spacing: 6) {
                if isMerging { CardArcSpinner(size: 10) }
                Text(isMerging ? "Merging…" : "Merge")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.hud(isMerging ? .arc : (mergeable ? .amber : .standard), size: .small))
        // Not-mergeable is disabled (and dimmed by the style); a running merge
        // stays enabled so the arc key isn't dimmed — the guard ignores taps.
        .disabled(!mergeable && !isMerging)
        .popover(isPresented: $showMergeConfirm) { mergeDialog }
    }
}

/// The gold "Update branch" control on a PR card's status row. Mirrors the
/// design's `UpdateBranchButton` (`.update-branch-btn` in `styles.css`): a small
/// radius-2 box in button vocabulary — deliberately *not* a status pill — gold
/// text on a gold wash at rest that fills solid gold (dark ink, glow) on hover. It sits immediately after
/// the local-status chip and appears only when the branch is behind its base.
///
/// It lives in the **status row, never the actions column**, so the trailing
/// Review / Merge controls stay uniform and the Merge buttons line up down
/// the list (a deliberate design decision — a conditional third action button
/// made the column width vary per row and broke that alignment).
///
/// Clicking it merges `origin/<base>` into the branch; while that runs the
/// control turns arc cyan with a spinning icon and is disabled. Once the branch is level
/// again (`behind == 0`) the parent stops rendering it.
struct UpdateBranchButton: View {
    /// Commits the branch is behind its base — drives the tooltip count. Nil
    /// when the count is unknown: the parent renders this view off GitHub's
    /// `BEHIND` state for a not-checked-out PR, where there's no local checkout
    /// to count against.
    let behind: Int?
    /// Runs the branch update. Awaited so the button can spin until the caller's
    /// re-sync settles and (on success) the branch is no longer behind.
    var onUpdate: () async -> Void = {}
    /// The medium row's shorter "Update" label.
    var label: String = "Update branch"

    @State private var busy = false
    @State private var hovering = false

    /// Pluralised tooltip — "…with 1 new commit…" / "…with 3 new commits…".
    /// Falls back to a count-free sentence when the behind count is unknown
    /// (nil) or non-positive. Static + internal so it's unit-testable without
    /// rendering the view.
    static func tooltip(behind: Int?) -> String {
        guard let behind, behind > 0 else {
            return "Update this branch with the latest changes from origin/main"
        }
        return "Update this branch with \(behind) new commit\(behind == 1 ? "" : "s") from origin/main"
    }

    private static let shape = RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)

    var body: some View {
        Button(action: tapped) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(busy ? 360 : 0))
                    .animation(
                        busy
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: busy
                    )
                Text(label)
                    .aerieFont(AerieFont.custom(.sans, size: 11).weight(.semibold))
                    .tracking(0.66) // 0.06em @ 11px
            }
            .foregroundStyle(foreground)
            // Matches `.update-branch-btn`: padding 3px 9px 3px 7px (less on the
            // leading edge so the icon optically aligns with the pills beside it).
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .padding(.vertical, 3)
            .background(fill, in: Self.shape)
            .overlay(Self.shape.strokeBorder(border, lineWidth: 1))
            .shadow(color: glow, radius: glow == .clear ? 0 : 9)
            .contentShape(Self.shape)
        }
        .buttonStyle(CopyLinkPressStyle())
        .disabled(busy)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: busy)
        .help(Self.tooltip(behind: behind))
        .fixedSize()
    }

    private var lit: Bool { hovering && !busy }

    private var foreground: Color {
        if busy { return AerieColor.arc }
        return lit ? AerieColor.amberInk : AerieColor.amber
    }

    private var fill: Color {
        if busy { return AerieColor.arcSoft }
        return lit ? AerieColor.amber : AerieColor.amberSoft
    }

    private var border: Color {
        if busy { return AerieColor.arcLine }
        return lit ? AerieColor.amber : AerieColor.amberLine
    }

    // `0 0 18px -3px var(--amber-glow)` on hover.
    private var glow: Color {
        if busy { return .clear }
        return lit ? AerieColor.amberGlow : .clear
    }

    private func tapped() {
        guard !busy else { return }
        Task {
            busy = true
            await onUpdate()
            busy = false
        }
    }
}

/// The quiet "copy link" icon button that pairs with Review on a PR card.
/// Mirrors the design's `CopyLinkButton` (`.copy-link-btn` in `v2/styles.css`):
/// a fixed 30×26 `.btn.ghost.sm` bevelled key that's grey at rest, hints gold on hover,
/// and — once the PR's GitHub URL is on the clipboard — flips to a green
/// checkmark for ~1.6s before settling back. That confirm-then-fade is the same
/// instant feedback language the Merge button uses, so the two read as one family.
///
/// The tooltip doubles as a preview: it shows the URL at rest ("Copy link · …")
/// and "Copied to clipboard" while the checkmark is up, so the user can see
/// exactly what lands on the clipboard.
struct CopyLinkButton: View {
    /// The GitHub URL to copy. The PR model already carries this as `htmlUrl`,
    /// so the owner is whatever GitHub returned for the repo.
    let url: URL

    @State private var copied = false
    @State private var hovering = false
    /// Resets the checkmark ~1.6s after the last copy. Re-clicking cancels the
    /// pending reset and starts a fresh one, so the confirmation always lingers
    /// a full window from the *latest* click — the design's `clearTimeout` +
    /// new `setTimeout(…, 1600)`.
    @State private var resetTask: Task<Void, Never>?

    private static let shape = HudKeyShape(cut: 6)

    var body: some View {
        Button(action: copy) {
            icon
                .foregroundStyle(foreground)
                .frame(width: 30, height: 26)
                .background(fill, in: Self.shape)
                .overlay(Self.shape.strokeBorder(border, lineWidth: 1))
                .contentShape(Self.shape)
        }
        .buttonStyle(CopyLinkPressStyle())
        .onHover { hovering = $0 }
        .help(copied ? "Copied to clipboard" : "Copy link · \(url.absoluteString)")
        .animation(.easeOut(duration: 0.15), value: copied)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    @ViewBuilder
    private var icon: some View {
        if copied {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
        } else {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .medium))
        }
    }

    // Resting grey → gold hint on hover → green once copied. The copied tint
    // wins over hover, matching `.copy-link-btn.copied:hover` (stays green).
    private var foreground: Color {
        if copied { return AerieColor.ok }
        return hovering ? AerieColor.amber : AerieColor.text3
    }
    private var fill: Color {
        if copied { return AerieColor.ok.opacity(0.14) }
        return hovering ? AerieColor.amberSoft : .clear
    }
    private var border: Color {
        if copied { return AerieColor.ok.opacity(0.45) }
        return hovering ? AerieColor.amberLine : .clear
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copied = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { copied = false }
        }
    }
}

/// The 0.5px press-sink shared by the card's quiet icon buttons — mirrors
/// `.copy-link-btn:active { transform: translateY(0.5px) }`.
private struct CopyLinkPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
