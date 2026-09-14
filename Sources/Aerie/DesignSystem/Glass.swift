import SwiftUI

/// Applies the Aerie MARK III plate treatment used on cards, dialogs, and the
/// window: a chamfered holographic plate with a conforming hairline edge,
/// a gold-lit left strut, and a faint warm sheen at the top.
/// (Design source: `styles.css` `.card`, `.window`.)
struct GlassModifier: ViewModifier {
    enum Variant { case window, card, dialog }
    let variant: Variant
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = HudPlateShape(cut: cut)
        return content
            .background(backgroundLayer)
            .clipShape(shape)
            .overlay(PlateEdge(shape: shape, emphasised: variant == .dialog))
            .overlay(alignment: .leading) {
                if variant == .card {
                    // `.card::after` — 2px gold strut down the left edge, brighter on hover.
                    // Inset 22pt top and bottom, but never more than a quarter of
                    // the plate — a one-line row would otherwise shrink the
                    // strut to a stray dot.
                    GeometryReader { geo in
                        let inset = min(22, geo.size.height * 0.25)
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: AerieColor.amberGlow, location: 0.3),
                            .init(color: AerieColor.amberGlow, location: 0.7),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(width: 2, height: max(0, geo.size.height - inset * 2))
                        .offset(y: inset)
                    }
                    .frame(width: 2)
                    .opacity(hovering ? 1 : 0.55)
                    .allowsHitTesting(false)
                }
            }
            .onHover { if variant == .card { hovering = $0 } }
            .animation(.easeOut(duration: 0.2), value: hovering)
    }

    private var cut: CGFloat {
        switch variant {
        case .window: return AerieMetric.cutWindow
        case .card:   return AerieMetric.cutCard
        case .dialog: return AerieMetric.cutDialog
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        let sheen = LinearGradient(stops: [
            .init(color: AerieColor.cardSheen.opacity(hovering ? 0.07 : 0.045), location: 0),
            .init(color: .clear, location: 0.36),
        ], startPoint: .top, endPoint: .bottom)
        switch variant {
        case .window:
            ZStack {
                AerieColor.glass1
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .opacity(0.8)
            }
        case .card:
            // Frosted plate: blur the desktop behind the translucent window,
            // washed with deep-space tint so text stays legible.
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                AerieColor.cardGlassTint
                (hovering ? AerieColor.glass3 : AerieColor.glass2)
                sheen
            }
        case .dialog:
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                AerieColor.dialogSurface
                sheen
            }
        }
    }
}

/// `.card::before` — the conforming hairline: a brighter top edge fading right,
/// a gold-lit upper third on the left, and struts across both clipped corners.
private struct PlateEdge: View {
    let shape: HudPlateShape
    var emphasised: Bool = false

    var body: some View {
        ZStack {
            shape.strokeBorder(emphasised ? AerieColor.glassLine2 : AerieColor.glassLine, lineWidth: 1)
            // Top edge: glass-line-2 fading out by 55%.
            shape.strokeBorder(AerieColor.glassLine2, lineWidth: 1)
                .mask(
                    LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.55)],
                                   startPoint: .leading, endPoint: .trailing)
                    .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.04)],
                                         startPoint: .top, endPoint: .bottom))
                )
            // Left edge: amber for the upper 34%.
            shape.strokeBorder(AerieColor.amberLine, lineWidth: 1)
                .mask(
                    LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.34), .init(color: .clear, location: 0.34)],
                                   startPoint: .top, endPoint: .bottom)
                    .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.02)],
                                         startPoint: .leading, endPoint: .trailing))
                )
        }
        .allowsHitTesting(false)
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
