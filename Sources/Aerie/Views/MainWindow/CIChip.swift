import SwiftUI

/// A pill-style chip that summarises the CI status of a pull request.
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` `StatusChip(kind="ci", ...)`.
/// A coloured dot followed by a short label, all on a transparent background —
/// the parent decides where to render it.
struct CIChip: View {
    let state: CIState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(AerieFont.small())
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
        case .success: return AerieColor.ok
        case .failure: return AerieColor.err
        case .pending: return AerieColor.warn
        case .none:    return AerieColor.text3
        }
    }

    private var textColor: Color {
        switch state {
        case .success: return AerieColor.ok
        case .failure: return AerieColor.err
        case .pending: return AerieColor.warn
        case .none:    return AerieColor.text3
        }
    }

    private var label: String {
        switch state {
        case .success: return "passed"
        case .failure: return "failing"
        case .pending: return "pending"
        case .none:    return "no checks"
        }
    }
}
