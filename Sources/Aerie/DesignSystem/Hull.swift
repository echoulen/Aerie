import SwiftUI

/// The MARK III window chassis (`styles.css .window`): content is clipped to
/// the asymmetric `HullShape`, edged with a 1px emitted gold gradient, and
/// dressed with hull furniture — bevel struts, left/right tick rails, and a
/// faint gold wash from the top.
///
/// The window itself is transparent (`AerieWindowChrome`), so the clipped
/// corners show the desktop through, reading as a cut-out chassis.
struct HullModifier: ViewModifier {
    /// Top-left bevel. The artboard uses 40px, but on macOS the native traffic
    /// lights live in that corner, so the real window keeps it small enough
    /// not to slice through them.
    var topLeftCut: CGFloat = 14

    func body(content: Content) -> some View {
        let hull = HullShape(topLeftCut: topLeftCut)
        // Every hull layer ignores the safe area. The window roots pull their
        // titlebar up under the native title bar with `.ignoresSafeArea`, but a
        // plain `clipShape` still measures from *below* that inset — it sliced
        // off the brand and the account avatar. Masking with a safe-area-ignoring
        // shape measures the hull from the real window top instead.
        content
            .mask { hull.fill().ignoresSafeArea() }
            .overlay {
                HullFurniture(topLeftCut: topLeftCut)
                    .mask { hull.fill() }
                    .ignoresSafeArea()
            }
            .overlay {
                hull.strokeBorder(
                    LinearGradient(stops: [
                        .init(color: AerieColor.hullEdgeA, location: 0),
                        .init(color: AerieColor.hullEdgeB, location: 0.30),
                        .init(color: Color(red: 1, green: 196/255, blue: 120/255).opacity(0.30), location: 0.58),
                        .init(color: Color(red: 1, green: 196/255, blue: 120/255).opacity(0.45), location: 1),
                    ], startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1)),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
            // `filter: drop-shadow(0 0 44px amber/0.30)` — the emitted glow.
            .background {
                hull.fill(AerieColor.space0.opacity(0.01))
                    .shadow(color: AerieColor.amber.opacity(0.22), radius: 22)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
    }
}

private struct HullFurniture: View {
    let topLeftCut: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                // Faint gold wash from above the top edge.
                RadialGradient(colors: [AerieColor.amber.opacity(0.07), .clear],
                               center: UnitPoint(x: 0.5, y: -0.12), startRadius: 0, endRadius: max(w, h) * 0.6)

                // Scanlines + interior glass sheen.
                LinearGradient(stops: [
                    .init(color: Color(red: 1, green: 206/255, blue: 140/255).opacity(0.05), location: 0),
                    .init(color: Color(red: 1, green: 206/255, blue: 140/255).opacity(0.014), location: 0.18),
                    .init(color: .clear, location: 0.46),
                ], startPoint: .top, endPoint: .bottom)

                // Bottom-right bevel strut, parallel to the clipped corner.
                Path { p in
                    let inset: CGFloat = 26 + 12
                    p.move(to: CGPoint(x: w - inset, y: h))
                    p.addLine(to: CGPoint(x: w, y: h - inset))
                }
                .stroke(AerieColor.amber.opacity(0.40), lineWidth: 1)

                // Left tick rail (every 14pt from 96pt down).
                TickRail(spacing: 14, color: AerieColor.glassLine2)
                    .frame(width: 7, height: max(0, h - 190))
                    .offset(x: 0, y: 96)

                // Right tick rail (every 22pt from 120pt down).
                TickRail(spacing: 22, color: AerieColor.glassLine)
                    .frame(width: 5, height: max(0, h - 220))
                    .offset(x: w - 5, y: 120)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Horizontal 1px ticks stacked vertically.
private struct TickRail: View {
    let spacing: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color))
                y += spacing
            }
        }
    }
}

extension View {
    /// Clip to the MARK III hull and draw its emitted edge + furniture.
    func aerieHull(topLeftCut: CGFloat = 14) -> some View {
        modifier(HullModifier(topLeftCut: topLeftCut))
    }
}
