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
    /// Reference "now" for the relative time string. Tests inject a fixed
    /// value to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()

    // MARK: - Derived presentation bits

    private var mergeable: Bool { Self.isMergeable(row.pr) }

    /// Whether the Merge button should light up. Prefer GitHub's authoritative
    /// `mergeStateStatus` (what the web UI gates on) over re-deriving from CI +
    /// review — repos differ on whether reviews/checks are *required*, so
    /// demanding an approval (or green CI) wrongly disabled mergeable PRs.
    /// Static + internal so it's unit-testable without rendering the view.
    static func isMergeable(_ pr: PullRequest) -> Bool {
        guard pr.state == .open else { return false }
        switch pr.mergeStateStatus {
        case "CLEAN", "UNSTABLE", "HAS_HOOKS", "BEHIND":
            // GitHub will accept the merge (no branch-protection block, no
            // conflicts). UNSTABLE = non-required checks pending/failing.
            return true
        case "DIRTY", "BLOCKED", "DRAFT":
            // Conflicts, blocked by branch protection, or a draft.
            return false
        default:
            // UNKNOWN, or older cached rows that predate the field: be
            // permissive — open and not actively blocked. Approval is NOT
            // required (many repos don't enforce reviews); only a hard failure
            // or an explicit "changes requested" holds the button back.
            return pr.ciState != .failure
                && pr.ciState != .pending
                && pr.reviewState != .changesRequested
        }
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
        } actions: {
            CardOpenButton(action: onOpen)
            mergeButton
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

    private var mergeButton: some View {
        Button(action: onMerge) {
            Text("Merge")
                .aerieFont(AerieFont.custom(.sans, size: 13).weight(mergeable ? .semibold : .medium))
                .foregroundStyle(mergeable ? AerieColor.amberInk : AerieColor.text2)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
        .fixedSize()
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
