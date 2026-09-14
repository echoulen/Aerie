import SwiftUI
import AppKit

/// The deep-space field the hull floats on (MARK III, `styles.css .backdrop`):
///   1. a burnt-orange nebula upper-right,
///   2. a violet nebula lower-left,
///   3. a faint cyan wash at the bottom,
///   4. a space-2 → space-0 base radial,
///   5. a tiled starfield drifting slowly up-left, and film-grain noise.
struct Backdrop: View {
    // --- Half-transparent glass knobs ---
    //
    // The window is made transparent in `AerieWindowChrome`; the behind-window
    // blur frosts whatever sits behind Aerie and `baseOpacity` controls how much
    // deep-space tint sits on top of it.
    var baseOpacity: Double = 0.88
    /// Frost (blur) the desktop behind the window rather than showing it crisply.
    var frostedGlass: Bool = true
    var glassMaterial: NSVisualEffectView.Material = .hudWindow
    /// Opacity of the behind-window blur layer.
    var blurStrength: Double = 0.62
    /// Multiplier on the nebula glows.
    var nebulaIntensity: Double = 1.0
    /// Flat black veil over everything.
    var dim: Double = 0.10
    /// Draw + drift the starfield. Snapshot tests may turn this off.
    var showsStars: Bool = true

    // oklch(0.62 0.19 40)
    private let nebulaWarm = Color(red: 0.876, green: 0.316, blue: 0.049)
    // oklch(0.48 0.20 300)
    private let nebulaViolet = Color(red: 0.446, green: 0.199, blue: 0.731)
    // oklch(0.58 0.16 215)
    private let nebulaCyan = Color(red: 0.0, green: 0.56, blue: 0.708)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                if frostedGlass {
                    VisualEffectBlur(material: glassMaterial, blendingMode: .behindWindow)
                        .opacity(blurStrength)
                }

                RadialGradient(
                    stops: [
                        .init(color: AerieColor.space2, location: 0),
                        .init(color: AerieColor.space1, location: 0.46),
                        .init(color: AerieColor.space0, location: 1),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.95
                )
                .opacity(baseOpacity)

                nebula(nebulaWarm, 0.30, at: UnitPoint(x: 0.82, y: 0.08), radius: w * 0.52 * 0.62)
                nebula(nebulaViolet, 0.34, at: UnitPoint(x: 0.12, y: 0.84), radius: w * 0.46 * 0.64)
                nebula(nebulaCyan, 0.18, at: UnitPoint(x: 0.62, y: 0.96), radius: w * 0.40 * 0.66)

                if showsStars {
                    Starfield()
                }

                Image("noise", bundle: .aerieResources)
                    .resizable()
                    .interpolation(.none)
                    .blendMode(.overlay)
                    .opacity(0.05)

                Color.black.opacity(dim)
            }
        }
        .ignoresSafeArea()
    }

    private func nebula(_ color: Color, _ alpha: Double, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color.opacity(min(alpha * nebulaIntensity, 1)), color.opacity(0)],
            center: center,
            startRadius: 0,
            endRadius: max(radius, 1)
        )
    }
}

/// `.backdrop::before` — eight tiled layers of 1–1.6px stars with different
/// tile sizes (so the pattern never visibly repeats), drifting -140/-90pt over
/// 210s. Drawn once into a rasterised layer; only its offset animates.
private struct Starfield: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifted = false

    private struct Layer {
        let size: CGFloat, tile: CGFloat, x: CGFloat, y: CGFloat, color: Color
    }

    private static let layers: [Layer] = [
        .init(size: 1.6, tile: 340, x: 0.20, y: 0.14, color: Color(red: 1, green: 244/255, blue: 226/255).opacity(0.95)),
        .init(size: 1.2, tile: 500, x: 0.72, y: 0.22, color: Color(red: 212/255, green: 232/255, blue: 1).opacity(0.85)),
        .init(size: 1.0, tile: 260, x: 0.42, y: 0.62, color: Color(red: 1, green: 236/255, blue: 210/255).opacity(0.80)),
        .init(size: 1.4, tile: 620, x: 0.88, y: 0.71, color: Color(red: 1, green: 222/255, blue: 190/255).opacity(0.85)),
        .init(size: 1.0, tile: 420, x: 0.12, y: 0.46, color: Color(red: 226/255, green: 238/255, blue: 1).opacity(0.70)),
        .init(size: 1.1, tile: 300, x: 0.58, y: 0.88, color: Color(red: 1, green: 246/255, blue: 232/255).opacity(0.75)),
        .init(size: 1.0, tile: 180, x: 0.32, y: 0.30, color: Color(red: 1, green: 236/255, blue: 214/255).opacity(0.55)),
        .init(size: 1.3, tile: 540, x: 0.92, y: 0.38, color: Color(red: 210/255, green: 228/255, blue: 1).opacity(0.65)),
    ]

    var body: some View {
        GeometryReader { geo in
            // Oversize by 20% on every side (`inset: -20%`) so the drift never
            // exposes an empty edge.
            let padX = geo.size.width * 0.2
            let padY = geo.size.height * 0.2
            Canvas { ctx, size in
                for layer in Self.layers {
                    var ty: CGFloat = 0
                    while ty < size.height {
                        var tx: CGFloat = 0
                        while tx < size.width {
                            let cx = tx + layer.tile * layer.x
                            let cy = ty + layer.tile * layer.y
                            let d = layer.size
                            ctx.fill(Path(ellipseIn: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)),
                                     with: .color(layer.color))
                            tx += layer.tile
                        }
                        ty += layer.tile
                    }
                }
            }
            .frame(width: geo.size.width + padX * 2, height: geo.size.height + padY * 2)
            .drawingGroup()
            .offset(x: -padX + (drifted ? -140 : 0), y: -padY + (drifted ? -90 : 0))
            .opacity(0.9)
        }
        .clipped()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 210).repeatForever(autoreverses: false)) {
                drifted = true
            }
        }
    }
}
