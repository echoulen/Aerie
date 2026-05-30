import SwiftUI

/// A single issue row, rendered as a glass card. The issue-side mirror of
/// ``PRCard``.
///
/// Visual contract: `v2/app.jsx` `IssueCard`. Layout:
///   ┌───────────────────────────────────────────────────────────────┐
///   │ <repo> · #N · <author> · [assigned to you] · <updated ago>    │
///   │                                                               │
///   │ <title>                                                       │
///   │                                                               │
///   │ <label pills…>  <💬 comments>                        [Open ↗]  │
///   └───────────────────────────────────────────────────────────────┘
struct IssueCard: View {
    let row: IssueRow
    var onOpen: () -> Void
    /// Reference "now" for the relative time string. Tests inject a fixed value
    /// to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()

    private var issue: Issue { row.issue }

    private var updatedAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        // GitHub's `updatedAt` can sit a few seconds ahead of the local clock
        // (e.g. the issue was just touched), which the formatter would render
        // as a future "in 9s" / "2 min" string. An update is always in the
        // past, so clamp the reference so the date is never after it.
        let reference = max(now, issue.updatedAt)
        return formatter.localizedString(for: issue.updatedAt, relativeTo: reference)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            leftColumn
            openButton
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .glass(.card)
    }

    // MARK: - Left column

    private var leftColumn: some View {
        // Uniform 12pt rhythm between meta · title · labels (the design's
        // `col { gap: 12 }`), so the top and bottom gaps read as equal.
        VStack(alignment: .leading, spacing: 12) {
            // Meta row
            HStack(spacing: 10) {
                Text(row.repo.name)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text2)
                dot
                Text("#\(issue.number)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                dot
                Text(issue.authorLogin)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                if issue.assignedToMe {
                    assignedPill
                }
                Spacer(minLength: 0)
                Text(updatedAgo)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }

            // Title
            Text(issue.title)
                .aerieFont(AerieFont.custom(.sans, size: 18).weight(.medium))
                .foregroundStyle(AerieColor.text1)
                .lineLimit(2)

            // Labels + comment count. The row reserves a constant height even
            // when an issue has no labels/comments, so a label-less card is the
            // same height as one with labels.
            HStack(spacing: 10) {
                ForEach(Array(issue.labels.enumerated()), id: \.offset) { _, label in
                    IssueLabelPill(label: label)
                }
                if issue.commentCount > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(AerieColor.text4)
                        Text("\(issue.commentCount)")
                            .aerieFont(AerieFont.code(12))
                            .foregroundStyle(AerieColor.text3)
                    }
                    .padding(.leading, 2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 24, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dot: some View {
        Text("·")
            .aerieFont(AerieFont.code(11))
            .foregroundStyle(AerieColor.text4)
    }

    private var assignedPill: some View {
        Text("assigned to you")
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

    // MARK: - Open button

    /// A compact, content-sized `Open ↗` control pinned to the trailing edge —
    /// per the design's `1fr auto` grid (the left column is greedy, this column
    /// is `auto`). Styled as the design's `.btn.ghost`: plain text, no fill or
    /// border (the padding still gives a comfortable click target).
    private var openButton: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Text("Open")
                Text("↗")
            }
            .aerieFont(AerieFont.custom(.sans, size: 13))
            .foregroundStyle(AerieColor.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// One issue label, rendered as a glass pill tinted with GitHub's own label
/// colour so the triage list keeps the colour coding users already know from
/// github.com. Falls back to a neutral pill when the colour can't be parsed.
struct IssueLabelPill: View {
    let label: IssueLabel

    var body: some View {
        let tint = Color(githubHex: label.color)
        let fg = tint ?? AerieColor.text3
        Text(label.name)
            .aerieFont(AerieFont.custom(.sans, size: 11).weight(.medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
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
