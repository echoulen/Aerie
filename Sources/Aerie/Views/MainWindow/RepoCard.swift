import SwiftUI

/// A single repository row, rendered as a glass card.
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` lines 313-366.
/// Layout:
///   ┌───────────────────────────────────────────────────────────────┐
///   │ <repo name>                                       ┌─────────┐ │
///   │ <owner/repo>                                      │  Open ↗ │ │
///   │ <collapsed local path>                            └─────────┘ │
///   │                                                  ┌──────────┐ │
///   │ <BranchTag> <dirty/clean> <DeltaView>            │Hard reset│ │
///   │                                                  └──────────┘ │
///   └───────────────────────────────────────────────────────────────┘
///
/// "Hard reset" is rendered amber UNLESS the working copy is on the default
/// branch AND clean (no dirty files, no divergence, no unpushed). In that
/// case the button is muted because there's nothing to reset to.
struct RepoCard: View {
    let row: RepoRow
    var onOpen: () -> Void
    var onHardReset: () -> Void

    // MARK: - Derived presentation bits

    private var repoTitle: String { row.repo.name }

    private var repoSubtitle: String {
        "\(row.repo.githubOwner)/\(row.repo.githubRepo)"
    }

    /// `$HOME/foo/bar` → `~/foo/bar`. Falls back to the raw path when the
    /// repo doesn't live under the user's home directory.
    private var collapsedPath: String {
        let raw = row.repo.localPath.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if raw == home { return "~" }
        if raw.hasPrefix(home + "/") {
            return "~" + raw.dropFirst(home.count)
        }
        return raw
    }

    private var branchName: String {
        row.status?.currentBranch ?? row.repo.defaultBranch
    }

    private var isOnDefault: Bool {
        guard let s = row.status else { return true }
        return s.currentBranch == row.repo.defaultBranch
    }

    /// "Clean" means: working copy is not dirty, no divergence vs origin
    /// default, and no unpushed commits. When `status == nil` we treat the
    /// repo as clean (we have no evidence to the contrary).
    private var isClean: Bool {
        guard let s = row.status else { return true }
        return s.isDirty == false
            && s.aheadOfDefault == 0
            && s.behindOfDefault == 0
            && s.unpushedCommits == 0
    }

    /// "Amber unless on clean default" — per Phase-10 plan.
    private var canHardReset: Bool {
        !(isOnDefault && isClean)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            leftColumn
            actions
                .frame(width: 140)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .glass(.card)
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title row: display name + owner/repo slug
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(repoTitle)
                    .font(.custom(AerieFont.sans, size: 17).weight(.medium))
                    .foregroundStyle(AerieColor.text1)
                Text(repoSubtitle)
                    .font(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }

            // Collapsed local path on its own line
            Text(collapsedPath)
                .font(AerieFont.code(11))
                .foregroundStyle(AerieColor.text3)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 4)

            // State row
            HStack(spacing: 20) {
                BranchTag(name: branchName, isCurrent: isOnDefault == false)
                dirtyOrClean
                if let status = row.status {
                    DeltaView(
                        ahead: status.aheadOfDefault,
                        behind: status.behindOfDefault,
                        unpushed: status.unpushedCommits
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var dirtyOrClean: some View {
        if let status = row.status, status.isDirty {
            HStack(spacing: 6) {
                Circle()
                    .fill(AerieColor.warn)
                    .frame(width: 6, height: 6)
                Text("uncommitted changes")
                    .font(AerieFont.code(12))
                    .foregroundStyle(AerieColor.warn)
            }
        } else if row.status != nil {
            Text("clean")
                .font(AerieFont.code(12))
                .foregroundStyle(AerieColor.text4)
        }
        // status == nil → render nothing for the dirty/clean slot.
    }

    // MARK: - Right column actions

    private var actions: some View {
        VStack(spacing: 10) {
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

            Button(action: onHardReset) {
                HStack(spacing: 8) {
                    ResetGlyph()
                        .frame(width: 12, height: 12)
                    Text("Hard reset")
                        .font(.custom(AerieFont.sans, size: 12.5).weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(canHardReset ? AerieColor.amber : AerieColor.text3)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(canHardReset ? AerieColor.amberSoft : AerieColor.glass2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(canHardReset ? AerieColor.amberLine : AerieColor.glassLine, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canHardReset)
        }
    }
}

/// Curved reset arrow used inside the Hard reset button. Mirrors the SVG in
/// `screens.jsx` `ResetGlyph()`.
private struct ResetGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let stroke = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x / 16 * s, y: y / 16 * s)
            }
            // Arc: M3 8 a5 5 0 018.7-3.4 L13 6
            var arc = Path()
            arc.move(to: p(3, 8))
            arc.addCurve(
                to: p(11.7, 4.6),
                control1: p(3, 5.2),
                control2: p(8.9, 4.6)
            )
            arc.addLine(to: p(13, 6))
            ctx.stroke(arc, with: .color(.primary), style: stroke)

            // Tip: M 13 3 v 3 h -3
            var tip = Path()
            tip.move(to: p(13, 3))
            tip.addLine(to: p(13, 6))
            tip.addLine(to: p(10, 6))
            ctx.stroke(tip, with: .color(.primary), style: stroke)
        }
    }
}
