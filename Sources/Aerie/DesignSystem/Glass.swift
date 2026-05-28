import SwiftUI

/// Applies the Aerie glass treatment used on cards, dialogs, and the window.
/// `backdrop: blur(40px) saturate(160%)`, `border 1px var(--glass-line)`,
/// `inset 0 1px 0 0 var(--glass-highlight)`.
struct GlassModifier: ViewModifier {
    enum Variant { case window, card, dialog }
    let variant: Variant

    func body(content: Content) -> some View {
        let blur: CGFloat = variant == .dialog ? 48 : 40
        let cornerRadius: CGFloat = variant == .window ? AerieMetric.radiusWindow : AerieMetric.radiusCard
        return content
            .background(
                ZStack {
                    AerieColor.glass1
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                        .opacity(blur / 50.0)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
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
