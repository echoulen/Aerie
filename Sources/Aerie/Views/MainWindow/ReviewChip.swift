import SwiftUI

/// A pill-style chip that summarises the review status of a pull request.
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` `StatusChip(kind="review", ...)`.
struct ReviewChip: View {
    let state: ReviewState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .aerieFont(AerieFont.small())
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .fill(AerieColor.glass2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }

    private var dotColor: Color {
        switch state {
        case .approved:         return AerieColor.ok
        case .changesRequested: return AerieColor.err
        case .reviewRequired:   return AerieColor.warn
        }
    }

    private var textColor: Color {
        switch state {
        case .approved:         return AerieColor.ok
        case .changesRequested: return AerieColor.err
        case .reviewRequired:   return AerieColor.warn
        }
    }

    private var label: String {
        switch state {
        case .approved:         return "approved"
        case .changesRequested: return "changes requested"
        case .reviewRequired:   return "review needed"
        }
    }
}
