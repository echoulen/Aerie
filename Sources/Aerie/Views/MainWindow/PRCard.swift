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

    /// Presentation-layer heuristic for "ready to merge". The `PullRequest`
    /// model doesn't yet carry an authoritative `mergeable` flag from
    /// GitHub — TODO: thread that through in a later phase. Static + internal
    /// so the heuristic is unit-testable without rendering the view.
    static func isMergeable(_ pr: PullRequest) -> Bool {
        guard pr.state == .open, pr.reviewState == .approved else { return false }
        // CI blocks the merge only when it's actively failing or still running.
        // A PR with no checks configured (`.none`) is mergeable — GitHub has no
        // required status to enforce, so the button must stay enabled.
        switch pr.ciState {
        case .success, .none:    return true
        case .failure, .pending: return false
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
