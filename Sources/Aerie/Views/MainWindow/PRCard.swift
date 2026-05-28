import SwiftUI

/// A single PR row, rendered as a glass card.
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` lines 155-242.
/// Layout:
///   ┌───────────────────────────────────────────────────────────────┐
///   │ <repo> · #N · <author> · [yours pill] · <updated ago>         │
///   │                                                               │
///   │ <title>                                                       │
///   │                                                               │
///   │ <CIChip> <ReviewChip> [ready to ship eyebrow]                 │
///   │ ────────────────────────────────────────────────────────────  │
///   │ LOCAL · <BranchTag> · <dirty/clean> · <DeltaView>             │
///   │                                                  [Merge] [↗]  │
///   └───────────────────────────────────────────────────────────────┘
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
    private var isReadyToShip: Bool {
        row.pr.state == .open
            && row.pr.reviewState == .approved
            && row.pr.ciState == .success
    }

    private var prMergeable: Bool { isReadyToShip }

    private var repoLabel: String { row.repo.name }

    private var updatedAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: row.pr.updatedAt, relativeTo: now)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            leftColumn
            actions
                .frame(minWidth: 140)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .glass(.card)
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Meta row
            HStack(spacing: 10) {
                Text(repoLabel)
                    .font(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text2)
                dot
                Text("#\(row.pr.number)")
                    .font(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                dot
                Text(row.pr.authorLogin)
                    .font(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                if row.pr.isMine {
                    yoursPill
                }
                Spacer(minLength: 0)
                Text(updatedAgo)
                    .font(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }

            // Title
            Text(row.pr.title)
                .font(.custom(AerieFont.sans, size: 19).weight(.medium))
                .foregroundStyle(AerieColor.text1)
                .lineLimit(2)
                .padding(.top, 10)
                .padding(.bottom, 16)

            // Status row
            HStack(spacing: 18) {
                CIChip(state: row.pr.ciState)
                ReviewChip(state: row.pr.reviewState)
                if isReadyToShip {
                    Text("READY TO SHIP")
                        .font(AerieFont.eyebrow())
                        .foregroundStyle(AerieColor.amber)
                        .tracking(1.2)
                }
                Spacer(minLength: 0)
            }

            // Local strip — only when we have local state to show.
            if let local = row.localState {
                Rectangle()
                    .fill(AerieColor.glassLine)
                    .frame(height: 1)
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                HStack(spacing: 22) {
                    Text("LOCAL")
                        .font(AerieFont.eyebrow())
                        .foregroundStyle(AerieColor.text4)
                        .tracking(1.6)

                    BranchTag(name: row.pr.sourceBranch, isCurrent: local.isCurrentBranch)

                    dirtyOrClean(local)

                    DeltaView(
                        ahead: local.ahead ?? 0,
                        behind: local.behind ?? 0,
                        unpushed: local.unpushed ?? 0
                    )

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func dirtyOrClean(_ local: PRLocalState) -> some View {
        if local.isCurrentBranch, local.dirty == true {
            HStack(spacing: 6) {
                Circle()
                    .fill(AerieColor.warn)
                    .frame(width: 6, height: 6)
                Text("dirty")
                    .font(AerieFont.code(12))
                    .foregroundStyle(AerieColor.warn)
            }
        } else {
            Text("clean")
                .font(AerieFont.code(12))
                .foregroundStyle(AerieColor.text4)
        }
    }

    private var dot: some View {
        Text("·")
            .font(AerieFont.code(11))
            .foregroundStyle(AerieColor.text4)
    }

    private var yoursPill: some View {
        Text("YOURS")
            .font(AerieFont.eyebrow())
            .foregroundStyle(AerieColor.amber)
            .tracking(1.2)
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

    // MARK: - Right column actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onMerge) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Merge")
                        .font(.custom(AerieFont.sans, size: 13).weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(prMergeable ? AerieColor.amber : AerieColor.text3)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(prMergeable ? AerieColor.amberSoft : AerieColor.glass2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(prMergeable ? AerieColor.amberLine : AerieColor.glassLine, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!prMergeable)

            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Text("Open")
                    Text("↗")
                }
                .font(.custom(AerieFont.sans, size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(AerieColor.text2)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AerieColor.glass2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
