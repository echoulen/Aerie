import SwiftUI

/// A single issue row. Renders through the shared ``CardContent`` skeleton, so
/// it stays pixel-consistent with the PR and Repo cards.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `IssueCard`:
///   ┌───────────────────────────────────────────────────────────────┐
///   │ <repo> · #N · <author> · [assigned to you] · <updated ago>    │
///   │ <title>                                              [Open ↗]   │
///   │ <label pills…>  <💬 comments>                                  │
///   └───────────────────────────────────────────────────────────────┘
///
/// Below regular width it mirrors the PR row's `compact.jsx` treatment (the
/// design has no issue-specific narrow artboard): one line at medium, three
/// stacked lines at compact; clicking the row opens the issue on GitHub.
struct IssueCard: View {
    let row: IssueRow
    var onOpen: () -> Void
    /// Reference "now" for the relative time string. Tests inject a fixed value
    /// to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()

    @Environment(\.widthClass) private var widthClass

    private var issue: Issue { row.issue }

    var body: some View {
        switch widthClass {
        case .regular:
            regularCard
        case .medium:
            mediumLine
                .adaptiveRowPlate(widthClass)
                .modifier(OpensOnClick(issue: issue, onOpen: onOpen))
        case .compact:
            compactLines
                .adaptiveRowPlate(widthClass)
                .modifier(OpensOnClick(issue: issue, onOpen: onOpen))
        }
    }

    /// title · assigned tag · first label · repo·#N · ↗
    private var mediumLine: some View {
        HStack(spacing: 11) {
            Text(issue.title)
                .aerieFont(AerieFont.custom(.sans, size: 13.5))
                .foregroundStyle(AerieColor.text1)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 12)
            if issue.assignedToMe { MiniPill(text: "assigned", tone: .amber) }
            if let label = issue.labels.first {
                IssueLabelPill(label: label, mini: true)
            }
            Text("\(row.repo.name)·\(issue.number)")
                .aerieFont(AerieFont.code(10.5))
                .foregroundStyle(AerieColor.text4)
                .lineLimit(1)
        }
    }

    /// meta line · wrapped title · labels + comment count
    private var compactLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(row.repo.name) · #\(issue.number)")
                    .aerieFont(AerieFont.code(10.5))
                    .tracking(0.84)
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
                if issue.assignedToMe { MiniPill(text: "assigned", tone: .amber) }
                Spacer(minLength: 4)
                Text(CardRelativeTime.label(for: issue.updatedAt, now: now))
                    .aerieFont(AerieFont.code(10.5))
                    .foregroundStyle(AerieColor.text4)
                    .fixedSize()
            }
            Text(issue.title)
                .aerieFont(AerieFont.custom(.sans, size: 13.5))
                .lineSpacing(4)
                .foregroundStyle(AerieColor.text1)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            if !issue.labels.isEmpty || issue.commentCount > 0 {
                HStack(alignment: .top, spacing: 8) {
                    FlowLayout(itemSpacing: 6, rowSpacing: 6) {
                        ForEach(Array(issue.labels.enumerated()), id: \.offset) { _, label in
                            IssueLabelPill(label: label, mini: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if issue.commentCount > 0 {
                        commentCount
                    }
                }
                .padding(.top, 9)
            }
        }
    }

    private var commentCount: some View {
        HStack(spacing: 5) {
            Image(systemName: "bubble.left")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(AerieColor.text4)
            Text("\(issue.commentCount)")
                .aerieFont(AerieFont.code(10.5))
                .foregroundStyle(AerieColor.text3)
        }
        .fixedSize()
    }

    private var regularCard: some View {
        CardContent(title: issue.title, updatedAt: issue.updatedAt, now: now) {
            CardMeta(
                name: row.repo.name,
                number: issue.number,
                author: issue.authorLogin,
                badge: issue.assignedToMe ? "assigned to you" : nil
            )
        } chips: {
            ForEach(Array(issue.labels.enumerated()), id: \.offset) { _, label in
                IssueLabelPill(label: label)
            }
            if issue.commentCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 11, weight: .regular))
                        .frame(width: 13, height: 13)
                        .foregroundStyle(AerieColor.text4)
                    Text("\(issue.commentCount)")
                        .aerieFont(AerieFont.code(12))
                        .foregroundStyle(AerieColor.text3)
                }
                .padding(.leading, 2)
            }
        } actions: {
            CardOpenButton(action: onOpen)
        }
    }
}

/// One issue label, rendered as a MARK III `.pill` (600 10.5pt uppercase,
/// 0.10em) tinted with GitHub's own label colour so the triage list keeps the
/// colour coding users already know from github.com. Falls back to a muted
/// pill (text-3) when the colour can't be parsed.
struct IssueLabelPill: View {
    let label: IssueLabel
    /// The narrow rows' dense `MiniPill` metrics (9pt, 1×6 padding).
    var mini: Bool = false

    var body: some View {
        let tint = Color(githubHex: label.color)
        let fg = tint ?? AerieColor.text3
        Text(label.name.uppercased())
            .aerieFont(AerieFont.custom(.sans, size: mini ? 9 : 10.5).weight(.semibold))
            .tracking(mini ? 0.9 : 1.05)
            .lineLimit(1)
            .foregroundStyle(fg)
            .padding(.horizontal, mini ? 6 : 9)
            .padding(.vertical, mini ? 1 : 3)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill((tint ?? AerieColor.glass2).opacity(tint == nil ? 1 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder((tint ?? AerieColor.glassLine).opacity(tint == nil ? 1 : 0.32), lineWidth: 1)
            )
    }
}

extension Color {
    /// Parses a GitHub label colour — a 6-digit hex string with no leading `#`
    /// (e.g. `"d73a4a"`). Returns nil for malformed input so callers can fall
    /// back to a neutral pill. Very dark labels are floored to a readable
    /// lightness so they don't vanish on the dark backdrop.
    init?(githubHex hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        var r = Double((value >> 16) & 0xFF) / 255
        var g = Double((value >> 8) & 0xFF) / 255
        var b = Double(value & 0xFF) / 255
        // Lift near-black labels toward grey so the text stays legible.
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luma < 0.25 {
            let lift = 0.35
            r = r + (1 - r) * lift
            g = g + (1 - g) * lift
            b = b + (1 - b) * lift
        }
        self.init(red: r, green: g, blue: b)
    }
}

/// Narrow issue rows open on GitHub when the row body is clicked.
private struct OpensOnClick: ViewModifier {
    let issue: Issue
    let onOpen: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .help("Open #\(issue.number) on GitHub")
    }
}
