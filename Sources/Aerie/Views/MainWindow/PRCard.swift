import SwiftUI

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

    /// Whether the amber "Update branch" pill should show for this row — only
    /// when the checked-out branch is behind its base (`behind > 0`). `behind`
    /// is nil unless the PR's branch is the current checkout, so this is also
    /// false for not-checked-out branches and missing local state. Static +
    /// internal so it's unit-testable without rendering the view.
    static func shouldShowUpdateBranch(_ local: PRLocalState?) -> Bool {
        (local?.behind ?? 0) > 0
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
            StatusPill(text: localStatus.text, tone: localStatus.tone)
            // Behind its base → offer a one-click update, glued right after the
            // sync chip (never the actions column). Drops out at behind == 0.
            if Self.shouldShowUpdateBranch(row.localState) {
                UpdateBranchButton(
                    behind: row.localState?.behind ?? 0,
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

    private static let actionColumnWidth: CGFloat = 108

    private var actionColumn: some View {
        VStack(spacing: 8) {
            openButton
            mergeButton
            checkoutButton
        }
        .frame(width: Self.actionColumnWidth)
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
    /// Commits the branch is behind its base — drives the tooltip count. The
    /// parent only renders this view when it's >= 1.
    let behind: Int
    /// Runs the branch update. Awaited so the button can spin until the caller's
    /// re-sync settles and (on success) the branch is no longer behind.
    var onUpdate: () async -> Void = {}

    @State private var busy = false

    /// Pluralised tooltip — "…with 1 new commit…" / "…with 3 new commits…".
    /// Static + internal so it's unit-testable without rendering the view.
    static func tooltip(behind: Int) -> String {
        "Update this branch with \(behind) new commit\(behind == 1 ? "" : "s") from origin/main"
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
