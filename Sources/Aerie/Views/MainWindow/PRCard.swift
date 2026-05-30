import SwiftUI

/// A single PR row, rendered as a glass card. The PR-side mirror of ``IssueCard``.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `PRCard`. Layout:
///   ┌───────────────────────────────────────────────────────────────┐
///   │ <repo> · #N · <author> · [yours] · <updated ago>             │
///   │                                                               │
///   │ <title>                                                       │
///   │                                                               │
///   │ <CI pill>  <Review pill>  <Local-state pill>   [Open ↗][Merge]│
///   └───────────────────────────────────────────────────────────────┘
///
/// The whole local-branch picture collapses into one calm sentence pill
/// (the design dropped the separate "LOCAL" strip with branch tag + deltas),
/// and the two actions sit side-by-side: a ghost "Open ↗" and a "Merge" that
/// only lights amber when CI passes *and* the PR is approved.
struct PRCard: View {
    let row: PRRow
    var onMerge: () -> Void
    var onOpen: () -> Void
    /// Reference "now" for the relative time string. Tests inject a fixed
    /// value to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()

    // MARK: - Derived presentation bits

    /// Presentation-layer heuristic for "ready to merge". The `PullRequest`
    /// model doesn't yet carry an authoritative `mergeable` flag from
    /// GitHub — TODO: thread that through in a later phase.
    private var mergeable: Bool {
        row.pr.state == .open
            && row.pr.reviewState == .approved
            && row.pr.ciState == .success
    }

    private var updatedAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        // An update is always in the past; clamp the reference so a few
        // seconds of clock skew never renders a future "in 9s" string.
        let reference = max(now, row.pr.updatedAt)
        return formatter.localizedString(for: row.pr.updatedAt, relativeTo: reference)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            leftColumn
            actions
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .glass(.card)
    }

    // MARK: - Left column

    private var leftColumn: some View {
        // Uniform 12pt rhythm between meta · title · status (the design's
        // `col { gap: 12 }`).
        VStack(alignment: .leading, spacing: 12) {
            // Meta row
            HStack(spacing: 10) {
                Text(row.repo.name)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text2)
                dot
                Text("#\(row.pr.number)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                dot
                Text(row.pr.authorLogin)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                if row.pr.isMine {
                    yoursPill
                }
                Spacer(minLength: 0)
                Text(updatedAgo)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }

            // Title
            Text(row.pr.title)
                .aerieFont(AerieFont.custom(.sans, size: 18).weight(.medium))
                .foregroundStyle(AerieColor.text1)
                .lineLimit(2)

            // Status row — CI · review · local, all in the same pill language.
            HStack(spacing: 10) {
                CIChip(state: row.pr.ciState)
                ReviewChip(state: row.pr.reviewState)
                StatusPill(text: localStatus.text, tone: localStatus.tone)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dot: some View {
        Text("·")
            .aerieFont(AerieFont.code(11))
            .foregroundStyle(AerieColor.text4)
    }

    private var yoursPill: some View {
        Text("yours")
            .aerieFont(AerieFont.eyebrow())
            .foregroundStyle(AerieColor.amber)
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(AerieColor.amberSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(AerieColor.amberLine, lineWidth: 1)
            )
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

    // MARK: - Right column actions

    /// `Open ↗` (ghost) then `Merge`, side-by-side per the design's
    /// `row { gap: 8 }`. The `auto` grid column sizes to the buttons.
    private var actions: some View {
        HStack(spacing: 8) {
            openButton
            mergeButton
        }
        .fixedSize()
    }

    private var openButton: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Text("Open")
                Text("↗")
            }
            .aerieFont(AerieFont.custom(.sans, size: 12))
            .foregroundStyle(AerieColor.text2)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

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
