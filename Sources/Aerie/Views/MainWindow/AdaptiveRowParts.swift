import SwiftUI

// Building blocks shared by the medium / compact variants of the PR, Issue and
// Repo rows (`compact.jsx` `CompactPRRow`, `CompactRepoRow`, `MediumPRList`).

/// The row plate for medium / compact rows: the same `.card` glass, with the
/// tighter 13×16 (medium) / 13×15 (compact) padding.
struct AdaptiveRowPlate: ViewModifier {
    let widthClass: WidthClass

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 13)
            .padding(.horizontal, widthClass == .compact ? 15 : 16)
            .glass(.card)
    }
}

extension View {
    func adaptiveRowPlate(_ widthClass: WidthClass) -> some View {
        modifier(AdaptiveRowPlate(widthClass: widthClass))
    }
}

/// A `.pill` shrunk to `padding 1px 6px`, `fontSize 9` — the dense tags the
/// narrow rows use in place of full sentence pills ("LOCAL", "DIRTY", "YOURS").
struct MiniPill: View {
    let text: String
    var tone: StatusPill.Tone = .neutral

    var body: some View {
        Text(text.uppercased())
            .aerieFont(AerieFont.custom(.sans, size: 9).weight(.semibold))
            .tracking(0.9)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: AerieMetric.radiusPill).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: AerieMetric.radiusPill).strokeBorder(border, lineWidth: 1))
            .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return AerieColor.text2
        case .muted:   return AerieColor.text3
        case .ok:      return AerieColor.ok
        case .warn:    return AerieColor.warn
        case .err:     return AerieColor.crimsonHot
        case .amber:   return AerieColor.amber
        case .arc:     return AerieColor.arc
        }
    }
    private var fill: Color {
        switch tone {
        case .neutral, .muted: return AerieColor.glass2
        case .ok:    return AerieColor.ok.opacity(0.10)
        case .warn:  return AerieColor.warn.opacity(0.10)
        case .err:   return AerieColor.crimsonSoft
        case .amber: return AerieColor.amberSoft
        case .arc:   return AerieColor.arcSoft
        }
    }
    private var border: Color {
        switch tone {
        case .neutral, .muted: return AerieColor.glassLine
        case .ok:    return AerieColor.ok.opacity(0.40)
        case .warn:  return AerieColor.warn.opacity(0.40)
        case .err:   return AerieColor.crimsonLine
        case .amber: return AerieColor.amberLine
        case .arc:   return AerieColor.arcLine
        }
    }
}

/// `.dot` — a 7pt status dot with a 10pt glow in its own colour.
struct StatusDot: View {
    let tone: StatusPill.Tone

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: tone == .muted ? .clear : color.opacity(0.85), radius: 5)
    }

    private var color: Color {
        switch tone {
        case .ok:      return AerieColor.ok
        case .warn:    return AerieColor.warn
        case .err:     return AerieColor.crimsonHot
        case .amber:   return AerieColor.amber
        case .arc:     return AerieColor.arc
        case .neutral, .muted: return AerieColor.text4
        }
    }
}

/// `↓3 ↑2` — behind (warn) / ahead (ok) commit counts in mono 10.5.
struct AheadBehindCounts: View {
    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: 8) {
            if behind > 0 {
                Text("↓\(behind)").foregroundStyle(AerieColor.warn)
            }
            if ahead > 0 {
                Text("↑\(ahead)").foregroundStyle(AerieColor.ok)
            }
        }
        .aerieFont(AerieFont.code(10.5))
        .fixedSize()
    }
}

/// The `⋯` overflow key (`btn ghost sm`, 3×8 padding) that holds a narrow
/// row's actions — every action the regular card shows inline stays reachable.
struct RowOverflowMenu<Items: View>: View {
    var help: String = "Actions"
    @ViewBuilder var items: () -> Items
    @State private var hovering = false

    private static var shape: HudKeyShape { HudKeyShape(cut: 6) }

    var body: some View {
        Menu {
            items()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(hovering ? AerieColor.text1 : AerieColor.text3)
        .frame(width: 30, height: 22)
        .background(Self.shape.fill(hovering ? AerieColor.glass2 : .clear))
        .overlay(Self.shape.strokeBorder(hovering ? AerieColor.glassLine : .clear, lineWidth: 1))
        .contentShape(Self.shape)
        .onHover { hovering = $0 }
        .help(help)
        .fixedSize()
    }
}

/// The single glyph key (`btn sm`, 3×9 padding) a medium row keeps inline —
/// "→" into the PR review, "↗" out to GitHub.
struct RowGlyphButton: View {
    let glyph: String
    var help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(glyph)
        }
        .buttonStyle(.hud(.standard, size: .small))
        .help(help)
        .fixedSize()
    }
}
