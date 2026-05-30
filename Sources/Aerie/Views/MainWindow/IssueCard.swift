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
struct IssueCard: View {
    let row: IssueRow
    var onOpen: () -> Void
    /// Reference "now" for the relative time string. Tests inject a fixed value
    /// to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()

    private var issue: Issue { row.issue }

    var body: some View {
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
                        .font(.system(size: 10, weight: .regular))
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
