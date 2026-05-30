import SwiftUI

/// A small status label — the design's `.pill` primitive.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` (the `.pill` class in
/// `styles.css` plus its tone modifiers `.ok` / `.warn` / `.err` / `.amber`).
/// A toned, glassy capsule with `500 11px` text, an optional leading status
/// dot, and a tint that matches the tone. Used by `CIChip`, `ReviewChip`, and
/// the PR card's local-state pill so every status reads in the same language.
struct StatusPill: View {
    /// The pill's colour family. `neutral` is the untinted glass pill;
    /// `muted` is the same untinted glass but with dimmer (`text-3`) text — it
    /// mirrors the design's `<span className="pill" style={{color:text-3}}>`.
    enum Tone { case neutral, ok, warn, err, amber, muted }

    let text: String
    var tone: Tone = .neutral
    /// When true, a tone-coloured 7pt dot leads the label (the design uses one
    /// for CI status, none for review/local).
    var showsDot: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showsDot {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }
            Text(text)
                .aerieFont(AerieFont.custom(.sans, size: 11).weight(.medium))
                .tracking(0.22) // letter-spacing 0.02em at 11px
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .fixedSize()
    }

    private var textColor: Color {
        switch tone {
        case .neutral: return AerieColor.text2
        case .ok:      return AerieColor.ok
        case .warn:    return AerieColor.warn
        case .err:     return AerieColor.err
        case .amber:   return AerieColor.amber
        case .muted:   return AerieColor.text3
        }
    }

    private var dotColor: Color {
        switch tone {
        case .neutral: return AerieColor.text3
        case .ok:      return AerieColor.ok
        case .warn:    return AerieColor.warn
        case .err:     return AerieColor.err
        case .amber:   return AerieColor.amber
        case .muted:   return AerieColor.text4
        }
    }

    private var fillColor: Color {
        switch tone {
        case .neutral, .muted: return AerieColor.glass2
        case .ok:    return AerieColor.ok.opacity(0.10)
        case .warn:  return AerieColor.warn.opacity(0.10)
        case .err:   return AerieColor.err.opacity(0.10)
        case .amber: return AerieColor.amberSoft
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral, .muted: return AerieColor.glassLine
        case .ok:    return AerieColor.ok.opacity(0.32)
        case .warn:  return AerieColor.warn.opacity(0.32)
        case .err:   return AerieColor.err.opacity(0.36)
        case .amber: return AerieColor.amberLine
        }
    }
}
