import SwiftUI

/// The shared content column for the PR and Issue list cards — the meta row
/// (`<repo> · #N · <author> · [badge] · <updated ago>`) above the title, with a
/// trailing slot for card-specific chips (issue labels + comment count, or PR
/// CI / review / local-status pills).
///
/// Standardised on the Issue card's design so both cards read identically:
/// a uniform 12pt vertical rhythm, an 18pt medium title, the clamped
/// relative-time string, and the amber ``CardBadge`` pill.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` (the PR/Issue card body).
struct CardContent<Chips: View>: View {
    let repo: String
    let number: Int
    let author: String
    /// Optional amber badge shown after the author — e.g. "assigned to you" on
    /// an issue, "yours" on a PR. Hidden when nil.
    var badge: String? = nil
    let title: String
    let updatedAt: Date
    /// Reference "now" for the relative-time string. Tests inject a fixed value
    /// to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()
    /// Card-specific chips rendered in the bottom row, leading-aligned.
    @ViewBuilder var chips: () -> Chips

    private var updatedAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        // `updatedAt` can sit a few seconds ahead of the local clock (e.g. the
        // item was just touched), which the formatter would render as a future
        // "in 9s". An update is always in the past, so clamp the reference so
        // the date is never after it.
        let reference = max(now, updatedAt)
        return formatter.localizedString(for: updatedAt, relativeTo: reference)
    }

    var body: some View {
        // Uniform 12pt rhythm between meta · title · chips (the design's
        // `col { gap: 12 }`), so the top and bottom gaps read as equal.
        VStack(alignment: .leading, spacing: 12) {
            // Meta row
            HStack(spacing: 10) {
                Text(repo)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text2)
                dot
                Text("#\(number)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                dot
                Text(author)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                if let badge {
                    CardBadge(text: badge)
                }
                Spacer(minLength: 0)
                Text(updatedAgo)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }

            // Title
            Text(title)
                .aerieFont(AerieFont.custom(.sans, size: 18).weight(.medium))
                .foregroundStyle(AerieColor.text1)
                .lineLimit(2)

            // Card-specific chips. The row reserves a constant height even when
            // empty, so a chip-less card is the same height as one with chips.
            HStack(spacing: 10) {
                chips()
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
}

/// The amber pill shown in a card's meta row — "assigned to you" on an issue,
/// "yours" on a PR. Standardised on the Issue card's styling.
struct CardBadge: View {
    let text: String

    var body: some View {
        Text(text)
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
}
