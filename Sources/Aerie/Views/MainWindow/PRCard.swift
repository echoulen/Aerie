import SwiftUI
import AppKit

/// A single PR row. Renders through the shared ``CardContent`` skeleton, so it
/// stays pixel-consistent with the Issue and Repo cards.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `PRCard`:
///   ┌───────────────────────────────────────────────────────────────┐
///   │ <repo> · #N · <author> · [yours] · <updated ago>             │
///   │ <title>                                       [Open ↗][Merge]  │
///   │ <CI pill>  <Review pill>  <Local-state pill>                  │
///   └───────────────────────────────────────────────────────────────┘
///
/// The whole local-branch picture collapses into one calm sentence pill, and
/// `Merge` only lights amber when CI passes *and* the PR is approved.
struct PRCard: View {
    let row: PRRow
    var onMerge: () -> Void
    var onOpen: () -> Void
    /// Asks the shell to present the force-checkout confirmation dialog for this
    /// PR. Defaulted to a no-op for snapshot tests and previews.
    var onCheckout: () -> Void = {}
    /// Opens the code review screen for this PR. Defaulted to a no-op for
    /// snapshot tests and previews.
    var onReview: () -> Void = {}
    /// Whether an AI review is currently running for this PR. When true the
    /// Review button swaps its chevron glyph for a spinner and reads
    /// "Reviewing…", mirroring the detail screen's `AIReviewButton`. Defaulted to
    /// `false` for snapshot tests and previews.
    var isReviewing: Bool = false
    /// Runs the base-branch update for this PR's checkout. Awaited by the
    /// status-row "Update branch" pill so it can spin until the row's sync
    /// settles. Defaulted to a no-op for snapshot tests and previews.
    var onUpdateBranch: () async -> Void = {}
    /// Reference "now" for the relative time string. Tests inject a fixed
    /// value to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()

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

    var body: some View {
        CardContent(title: row.pr.title, updatedAt: row.pr.updatedAt, now: now) {
            CardMeta(
                name: row.repo.name,
                number: row.pr.number,
                author: row.pr.authorLogin,
                badge: row.pr.isMine ? "yours" : nil
            )
        } chips: {
            CIChip(state: row.pr.ciState)
            ReviewChip(state: row.pr.reviewState)
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
        }
    }

    // MARK: - Actions column
    //
    // Open · Merge · Checkout stacked top→bottom, equal width and centred — the
    // design's `PRCard` right column (`v2/app.jsx`: "actions, stacked top →
    // bottom"). All three are `.btn.sm` (12pt) sized; Open is ghost (borderless),
    // Merge/Checkout carry the glass/amber `.btn` chrome. A fixed column width
    // keeps the three equal and the cards' action columns aligned down the list.
    //
    // Open shares its top row with a small ``CopyLinkButton`` (`v2/app.jsx`: the
    // Open `flex:1` button paired with the fixed 30pt copy icon). The pair sits
    // above Merge/Checkout so the copy affordance never crowds them. The column
    // widens to 132 to match the design's `minWidth: 132` and give Open room
    // beside the copy icon.

    private static let actionColumnWidth: CGFloat = 132

    private var actionColumn: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                openButton
                CopyLinkButton(url: row.pr.htmlUrl)
            }
            reviewButton
            mergeButton
            checkoutButton
        }
        .frame(width: Self.actionColumnWidth)
    }

    // Glass-chrome button (matches Checkout) that drills into the code review
    // screen — the in-app "read the diff → approve" entry point.
    private var reviewButton: some View {
        Button(action: onReview) {
            HStack(spacing: 6) {
                if isReviewing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(isReviewing ? "Reviewing…" : "Review")
            }
            .aerieFont(AerieFont.custom(.sans, size: 12))
            .foregroundStyle(AerieColor.text1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AerieColor.glass2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Review the diff for \(row.repo.name) #\(row.pr.number)")
    }

    private var openButton: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Text("Open")
                Text("↗")
            }
            .aerieFont(AerieFont.custom(.sans, size: 12))
            .foregroundStyle(AerieColor.text2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var checkoutButton: some View {
        let plan = CheckoutPlan.make(for: row.localState)
        // Destructive checkouts hint with red label text (design: `color:
        // destructive ? red : text-1`); the nuance otherwise lives in the dialog.
        let tint = plan.destructive ? AerieColor.err : AerieColor.text1
        return Button(action: onCheckout) {
            HStack(spacing: 6) {
                CheckoutGlyphShape()
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6 * 11 / 16, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 11)
                Text("Checkout")
            }
            .aerieFont(AerieFont.custom(.sans, size: 12))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AerieColor.glass2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(plan.current
            ? "Local repo is already on origin/\(row.pr.sourceBranch)"
            : "Force checkout \(row.repo.name) to origin/\(row.pr.sourceBranch)")
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

    private var mergeButton: some View {
        Button(action: onMerge) {
            Text("Merge")
                .aerieFont(AerieFont.custom(.sans, size: 12).weight(mergeable ? .semibold : .medium))
                .foregroundStyle(mergeable ? AerieColor.amberInk : AerieColor.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(mergeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(mergeable ? AerieColor.amberCtaLine : AerieColor.glassLine, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(mergeable ? 1 : 0.45)
        .disabled(!mergeable)
    }

    @ViewBuilder
    private var mergeBackground: some View {
        if mergeable {
            // The design's `.btn.amber`: vertical amber gradient + bright top edge.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AerieColor.amberFillTop, AerieColor.amberFillBot],
                        startPoint: .top, endPoint: .bottom
                    )
                )
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
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AerieColor.glass2)
        }
    }
}

/// The amber "Update branch" control on a PR card's status row. Mirrors the
/// design's `UpdateBranchButton` (`.update-branch-btn` in `styles.css`): a small
/// amber, square-cornered button — deliberately *not* a round status pill — that
/// sits immediately after the local-status chip and appears only when the
/// checked-out branch is behind its base.
///
/// It lives in the **status row, never the actions column**, so the trailing
/// `Open ↗` / `Merge` controls stay uniform and the Merge buttons line up down
/// the list (a deliberate design decision — a conditional third action button
/// made the column width vary per row and broke that alignment).
///
/// Clicking it merges `origin/<base>` into the branch; while that runs the icon
/// spins and the button is disabled. Once the branch is level again
/// (`behind == 0`) the parent stops rendering it.
struct UpdateBranchButton: View {
    /// Commits the branch is behind its base — drives the tooltip count. Nil
    /// when the count is unknown: the parent renders this view off GitHub's
    /// `BEHIND` state for a not-checked-out PR, where there's no local checkout
    /// to count against.
    let behind: Int?
    /// Runs the branch update. Awaited so the button can spin until the caller's
    /// re-sync settles and (on success) the branch is no longer behind.
    var onUpdate: () async -> Void = {}

    @State private var busy = false

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
                Text("Update branch")
                    .aerieFont(AerieFont.custom(.sans, size: 11.5).weight(.medium))
            }
            .foregroundStyle(AerieColor.amber)
            // Matches `.update-branch-btn`: padding 3px 9px 3px 7px (less on the
            // leading edge so the icon optically aligns), 7pt square-ish corners.
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AerieColor.amberSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(AerieColor.amberLine, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
        .help(Self.tooltip(behind: behind))
        .fixedSize()
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

/// The quiet "copy link" icon button that pairs with `Open ↗` on a PR card.
/// Mirrors the design's `CopyLinkButton` (`.copy-link-btn` in `v2/styles.css`):
/// a fixed 30×26 ghost square that's grey at rest, hints amber on hover, and —
/// once the PR's GitHub URL is on the clipboard — flips to a green checkmark for
/// ~1.6s before settling back. That confirm-then-fade is the same instant
/// feedback language the Merge button uses, so the two read as one family.
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

    var body: some View {
        Button(action: copy) {
            icon
                .foregroundStyle(foreground)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

    // Resting grey → amber hint on hover → green once copied. The copied tint
    // wins over hover, matching `.copy-link-btn.copied:hover` (stays green).
    private var foreground: Color {
        if copied { return AerieColor.ok }
        return hovering ? AerieColor.amber : AerieColor.text3
    }
    private var fill: Color {
        if copied { return AerieColor.ok.opacity(0.14) }
        return hovering ? AerieColor.amber.opacity(0.10) : .clear
    }
    private var border: Color {
        if copied { return AerieColor.ok.opacity(0.45) }
        return hovering ? AerieColor.amber.opacity(0.40) : .clear
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
