import SwiftUI

/// A single repository row, rendered as a glass card.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `RepoCard(...)`.
/// Three columns share one piece of glass:
///   ┌──────────────────────────────────────────────────────────────────┐
///   │ <owner> · [off default]                                            │
///   │ <name>                     ● <status sentence>   Open ↗  [Reset…] │
///   │ ⎇ <branch>                                                         │
///   └──────────────────────────────────────────────────────────────────┘
/// - Identity: owner + (when off the default branch) an "off default" pill,
///   the repo name (20pt medium), and the checked-out branch as a plain
///   glyph + mono name (no bordered tag).
/// - Status: a single tone-coloured dot + one calm sentence — "Working tree
///   dirty", "Clean · in sync with origin", or an "N ahead · M behind …"
///   summary — replacing the old inline dirty/clean + delta chips.
/// - Actions: a ghost "Open ↗" and a red `.btn.danger` "Reset to origin/<b>".
///   Per the v2 design the reset action is always offered (no muted state).
struct RepoCard: View {
    let row: RepoRow
    var onOpen: () -> Void
    var onHardReset: () -> Void

    // MARK: - Derived presentation bits

    private var repoTitle: String { row.repo.name }
    private var owner: String { row.repo.githubOwner }
    private var defaultBranch: String { row.repo.defaultBranch }

    private var branchName: String {
        row.status?.currentBranch ?? row.repo.defaultBranch
    }

    private var isOnDefault: Bool {
        guard let s = row.status else { return true }
        return s.currentBranch == row.repo.defaultBranch
    }

    private enum StatusTone { case ok, warn, amber }

    /// Mirrors `app.jsx`: clean → ok, dirty → warn, otherwise an
    /// ahead/behind/unpushed summary → amber. `nil` status reads as clean
    /// (we have no evidence to the contrary).
    private var statusTone: StatusTone {
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

    private var statusColor: Color {
        switch statusTone {
        case .ok:    return AerieColor.ok
        case .warn:  return AerieColor.warn
        case .amber: return AerieColor.amber
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            identityColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            statusColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 26)
        .glass(.card)
    }

    // MARK: - Identity column

    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(owner)
                    .font(.custom(AerieFont.sans, size: 12))
                    .foregroundStyle(AerieColor.text3)
                if !isOnDefault {
                    Text("·")
                        .font(.custom(AerieFont.sans, size: 12))
                        .foregroundStyle(AerieColor.text4)
                    offDefaultPill
                }
            }

            Text(repoTitle)
                .font(.custom(AerieFont.sans, size: 20).weight(.medium))
                .tracking(-0.16)                 // -0.008em @ 20pt
                .foregroundStyle(AerieColor.text1)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                BranchGlyph()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(AerieColor.text3)
                Text(branchName)
                    .font(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 2)
        }
    }

    private var offDefaultPill: some View {
        Text("off default")
            .font(.custom(AerieFont.sans, size: 10))
            .foregroundStyle(AerieColor.text3)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule(style: .continuous).fill(AerieColor.glass2))
            .overlay(Capsule(style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }

    // MARK: - Status column

    private var statusColumn: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.6), radius: 4)
            Text(statusText)
                .font(.custom(AerieFont.sans, size: 13.5))
                .foregroundStyle(AerieColor.text2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            GhostButton(title: "Open ↗", action: onOpen)
            DangerButton(title: "Reset to origin/\(defaultBranch)", action: onHardReset)
        }
    }
}

// MARK: - Buttons

/// `.btn.ghost.sm` — transparent until hover, where it gains a `glass2` fill
/// and brightens to `text1`. 12pt sans, 5×10 padding, 9pt radius.
private struct GhostButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(AerieFont.sans, size: 12))
                .foregroundStyle(hovering ? AerieColor.text1 : AerieColor.text3)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hovering ? AerieColor.glass2 : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// `.btn.danger` — lighter-red text on an `err`-tinted fill with a matching
/// hairline; the fill deepens on hover. 13pt medium sans, 8×14 padding.
private struct DangerButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(AerieFont.sans, size: 13).weight(.medium))
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
