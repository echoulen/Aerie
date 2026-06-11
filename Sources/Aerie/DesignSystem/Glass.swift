import SwiftUI

/// Applies the Aerie glass treatment used on cards, dialogs, and the window.
/// `backdrop: blur(40px) saturate(160%)`, `border 1px var(--glass-line)`,
/// `inset 0 1px 0 0 var(--glass-highlight)`.
struct GlassModifier: ViewModifier {
    enum Variant { case window, card, dialog }
    let variant: Variant

    func body(content: Content) -> some View {
        let cornerRadius: CGFloat = self.cornerRadius
        return content
            .background(backgroundLayer)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AerieColor.glassHighlight, lineWidth: 1)
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .window: return AerieMetric.radiusWindow
        case .card:   return AerieMetric.radiusCard
        case .dialog: return AerieMetric.radiusDialog
        }
    }

    // Dialog needs the brighter glass-line-2 ring so it reads as a raised
    // surface against the dimmed scrim (matches the design's accent ring).
    // Window/card stay on the subtler glass-line.
    private var borderColor: Color {
        variant == .dialog ? AerieColor.glassLine2 : AerieColor.glassLine
    }

    // Per `styles.css`:
    //   .window → glass-1 (0.035) + behindWindow frosted material
    //   .card   → within-window blur + `cardGlassTint`: a frosted-glass panel
    //             that blurs the now-translucent backdrop showing behind it.
    //             (Was a flat/opaque fill; the window is translucent now, so the
    //             card frosts what shows through instead of sitting solid.)
    //   .dialog → dark `dialogSurface` (rgba(28,26,32,0.78)) layered over a
    //             within-window blur. The old white-glass + `.menu` material
    //             rendered too bright in dark mode; this matches the design's
    //             dark dialog body + `backdrop-filter blur(48px)`.
    @ViewBuilder
    private var backgroundLayer: some View {
        switch variant {
        case .window:
            ZStack {
                AerieColor.glass1
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .opacity(0.8)
            }
        case .card:
            // Frosted glass: blur the desktop showing through the translucent
            // window *behind* the card, washed with a dark tint so text stays
            // legible. Must be `.behindWindow` (not `.withinWindow`): the desktop
            // is composited behind the window, so a within-window blur has no
            // crisp content to frost and reads as a flat tint.
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                AerieColor.cardGlassTint
            }
        case .dialog:
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                AerieColor.dialogSurface
            }
        }
    }
}

extension View {
    func glass(_ variant: GlassModifier.Variant = .card) -> some View {
        modifier(GlassModifier(variant: variant))
    }
}

/// NSVisualEffectView bridge.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
