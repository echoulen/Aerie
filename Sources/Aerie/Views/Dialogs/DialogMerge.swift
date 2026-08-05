import SwiftUI

/// Confirmation content for squash-merging a pull request, presented via
/// `.popover(isPresented:)` anchored to the PR card's Merge button. Amber
/// tone + a compact PR preview (title, owner/repo, number, author, CI +
/// review chips) above a KV summary (method, commit subject, source branch,
/// account).
///
/// Carries no busy/error state of its own — `onConfirm` fires once,
/// synchronously; the caller closes the popover immediately and hands off to
/// `PRActionStore` for the actual (backgrounded) merge + failure reporting.
struct DialogMerge: View {
    let pr: PullRequest
    let repo: Repository
    let account: GitHubAccount
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ActionPopoverShell(
            tone: .warning,
            title: "Merge pull request #\(pr.number)?",
            subtitle: "Squash and merge using \(account.login). The source branch will be deleted on \(account.host) after merging.",
            primaryTitle: "Merge",
            onPrimary: onConfirm,
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            iconView: AnyView(MergeGlyph(color: AerieColor.amber)),
            primaryProminent: true,
            headerSpacing: 7,
            titleWeight: .regular
        ) {
            VStack(spacing: 14) {
                preview
                KVList(rows: [
                    KVList.Row("method", AnyView(mono("squash + merge"))),
                    KVList.Row("commit subj", AnyView(mono("\(pr.title) (#\(pr.number))"))),
                    KVList.Row("account", AnyView(mono("\(account.login) · \(account.host)"))),
                ])
            }
        }
    }

    // PR preview card — mirrors the design's `DialogMerge` preview: a
    // `repo · #N` eyebrow, the PR title, then an inline status row. The design's
    // row also shows check counts, the approver's login, and +/- diff stats;
    // our `PullRequest` model doesn't track those, so we surface the CI + review
    // state we do have, in the same inline-text style.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(repo.githubRepo) · #\(pr.number)")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
            Text(pr.title)
                .aerieFont(AerieFont.custom(.sans, size: 14.5).weight(.light))
                .foregroundStyle(AerieColor.text1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 14) {
                ciSummary
                reviewSummary
                diffSummary
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(13))
            .foregroundStyle(AerieColor.text1)
    }

    @ViewBuilder
    private var ciSummary: some View {
        switch pr.ciState {
        case .success: statusText("✓ CI passing", AerieColor.ok)
        case .failure: statusText("✕ CI failing", AerieColor.err)
        case .pending: statusText("• CI pending", AerieColor.text3)
        case .none:    statusText("No checks", AerieColor.text3)
        }
    }

    @ViewBuilder
    private var reviewSummary: some View {
        switch pr.reviewState {
        case .approved:
            if let approver = pr.approvedBy {
                statusText("✓ approved by \(approver)", AerieColor.ok)
            } else {
                statusText("✓ Approved", AerieColor.ok)
            }
        case .changesRequested: statusText("Changes requested", AerieColor.err)
        case .reviewRequired:   statusText("Review requested", AerieColor.text3)
        }
    }

    // Diff size, mirroring the design's "+312 -184 · 7 files" run: additions in
    // ok-green, deletions in err-red, file count muted. Only shown when the
    // fetch supplied the numbers (older cached PRs predate them).
    @ViewBuilder
    private var diffSummary: some View {
        if let add = pr.additions, let del = pr.deletions, let files = pr.changedFiles {
            HStack(spacing: 5) {
                Text("+\(add)")
                    .aerieFont(AerieFont.code(12))
                    .foregroundStyle(AerieColor.ok)
                Text("-\(del)")
                    .aerieFont(AerieFont.code(12))
                    .foregroundStyle(AerieColor.err)
                Text("· \(files) \(files == 1 ? "file" : "files")")
                    .aerieFont(AerieFont.custom(.sans, size: 12))
                    .foregroundStyle(AerieColor.text3)
            }
        }
    }

    private func statusText(_ text: String, _ color: Color) -> some View {
        Text(text)
            .aerieFont(AerieFont.custom(.sans, size: 12))
            .foregroundStyle(color)
    }

}

/// The design's git-merge glyph (`v2/dialogs.jsx` `MergeIcon`): two nodes on a
/// left trunk, a third branching up on the right, and a small merge arrow at the
/// top. Drawn from the SVG's 16×16 coordinates so it matches pixel-for-pixel
/// rather than approximating with an SF Symbol.
private struct MergeGlyph: View {
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 16
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let stroke = StrokeStyle(lineWidth: 1.5 * s, lineCap: .round, lineJoin: .round)

            var lines = Path()
            lines.move(to: p(4, 4.5));   lines.addLine(to: p(4, 11.5))    // left trunk
            lines.move(to: p(12, 7));    lines.addLine(to: p(12, 11.5))   // right branch
            lines.move(to: p(8.5, 2.5)); lines.addLine(to: p(11.5, 5.5)); lines.addLine(to: p(8.5, 5.5)) // merge arrow
            ctx.stroke(lines, with: .color(color), style: stroke)

            for c in [p(4, 3), p(4, 13), p(12, 13)] {
                let r = 1.5 * s
                let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.stroke(dot, with: .color(color), style: stroke)
            }
        }
        .frame(width: 17, height: 17)
    }
}
