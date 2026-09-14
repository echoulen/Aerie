import SwiftUI
import AppKit

/// The deep-space field the hull floats on (MARK III, `styles.css .backdrop`).
/// Everything is slowly adrift:
///   1. three nebula clouds (burnt orange upper-right, violet lower-left, a faint
///      cyan wash at the bottom) swimming against each other (`nebulaSeconds`),
///   2. a space-2 → space-0 base radial,
///   3. a near starfield — bigger, brighter, twinkling — drifting up-left fastest,
///   4. a far starfield — finer, dimmer — crawling the same way, slower, for parallax,
///   5. film-grain noise.
/// With Reduce Motion on, every layer holds still.
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
    /// Draw the starfield. Snapshot tests may turn this off.
    var showsStars: Bool = true

    /// One sweep of the nebula swim. The design's CSS uses 320s, which reads as
    /// static in the app; this is sped up so the motion is actually visible.
    static let nebulaSeconds: Double = 60

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `aerie-nebula` keyframe: false = 0%, true = 100% (alternating).
    @State private var nebulaPhase = false

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

                // Each nebula is painted on a 200%×200% background tile whose
                // position swings between two keyframes, so its centre is
                // `2·gradientPos − bgPos` of the box. Radii are % of the 2× tile.
                ZStack {
                    nebula(nebulaWarm, 0.30, fade: 0.62, size: geo.size,
                           gradientAt: CGPoint(x: 0.82, y: 0.08), radii: CGSize(width: 0.52, height: 0.44),
                           bgFrom: CGPoint(x: 0.42, y: 0.44), bgTo: CGPoint(x: 0.58, y: 0.56))
                    nebula(nebulaViolet, 0.34, fade: 0.64, size: geo.size,
                           gradientAt: CGPoint(x: 0.12, y: 0.84), radii: CGSize(width: 0.46, height: 0.52),
                           bgFrom: CGPoint(x: 0.58, y: 0.56), bgTo: CGPoint(x: 0.42, y: 0.44))
                    nebula(nebulaCyan, 0.18, fade: 0.66, size: geo.size,
                           gradientAt: CGPoint(x: 0.62, y: 0.96), radii: CGSize(width: 0.40, height: 0.40),
                           bgFrom: CGPoint(x: 0.50, y: 0.48), bgTo: CGPoint(x: 0.50, y: 0.54))
                }
                .drawingGroup()

                if showsStars {
                    StarLayer(layers: StarLayer.near, direction: CGSize(width: -2, height: -1),
                              speed: 6, twinkles: true)
                    // Same heading as the near layer, just slower — parallax
                    // by speed. (The design's CSS sends the far layer the
                    // other way, which read as stars scattering, not a sky.)
                    StarLayer(layers: StarLayer.far, direction: CGSize(width: -2, height: -1),
                              speed: 2.5, twinkles: false)
                        .opacity(0.8)
                }

                Image("noise", bundle: .aerieResources)
                    .resizable()
                    .interpolation(.none)
                    .blendMode(.overlay)
                    .opacity(0.045)

                Color.black.opacity(dim)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Self.nebulaSeconds).repeatForever(autoreverses: true)) {
                nebulaPhase = true
            }
        }
    }

    private func nebula(
        _ color: Color, _ alpha: Double, fade: CGFloat, size: CGSize,
        gradientAt g: CGPoint, radii: CGSize, bgFrom: CGPoint, bgTo: CGPoint
    ) -> some View {
        let bg = nebulaPhase ? bgTo : bgFrom
        let center = CGPoint(x: (2 * g.x - bg.x) * size.width, y: (2 * g.y - bg.y) * size.height)
        let rx = max(radii.width * 2 * size.width, 1)
        let ry = max(radii.height * 2 * size.height, 1)
        return EllipticalGradient(
            stops: [
                .init(color: color.opacity(min(alpha * nebulaIntensity, 1)), location: 0),
                .init(color: color.opacity(0), location: fade),
            ],
            center: .center
        )
        .frame(width: rx * 2, height: ry * 2)
        .position(center)
    }
}

/// One parallax star layer (`.backdrop::before` near / `::after` far): tiled
/// dots of different tile sizes so the pattern never visibly repeats.
///
/// Each dot set is its own rasterised layer that travels exactly
/// `direction × tile` per loop, so when the linear animation restarts the
/// tiling lands back on itself — no visible jump. Travel speed is in pt/s; the
/// design's CSS drift (150s / 420s) was too slow to notice, so these run faster.
private struct StarLayer: View {
    struct Dot {
        let size: CGFloat, tile: CGFloat, x: CGFloat, y: CGFloat, color: Color
    }

    /// Near stars — bigger, brighter, drifting fastest.
    static let near: [Dot] = [
        .init(size: 1.7, tile: 340, x: 0.20, y: 0.14, color: Color(red: 1, green: 244/255, blue: 226/255).opacity(0.95)),
        .init(size: 1.5, tile: 500, x: 0.72, y: 0.22, color: Color(red: 212/255, green: 232/255, blue: 1).opacity(0.90)),
        .init(size: 1.4, tile: 620, x: 0.88, y: 0.71, color: Color(red: 1, green: 222/255, blue: 190/255).opacity(0.88)),
        .init(size: 1.6, tile: 430, x: 0.42, y: 0.62, color: Color(red: 1, green: 236/255, blue: 210/255).opacity(0.85)),
    ]

    /// Far stars — finer, dimmer, crawling the same way more slowly.
    static let far: [Dot] = [
        .init(size: 1.0, tile: 260, x: 0.12, y: 0.46, color: Color(red: 226/255, green: 238/255, blue: 1).opacity(0.72)),
        .init(size: 1.0, tile: 300, x: 0.58, y: 0.88, color: Color(red: 1, green: 246/255, blue: 232/255).opacity(0.70)),
        .init(size: 0.9, tile: 180, x: 0.32, y: 0.30, color: Color(red: 1, green: 236/255, blue: 214/255).opacity(0.58)),
        .init(size: 1.1, tile: 540, x: 0.92, y: 0.38, color: Color(red: 210/255, green: 228/255, blue: 1).opacity(0.62)),
        .init(size: 0.8, tile: 220, x: 0.66, y: 0.08, color: Color(red: 1, green: 240/255, blue: 220/255).opacity(0.50)),
    ]

    let layers: [Dot]
    /// Travel per loop, in tiles (integers keep the loop seamless). Both layers
    /// head up-left at roughly the design's 1.7 : 1 drift angle.
    let direction: CGSize
    /// Travel speed in pt/s.
    let speed: CGFloat
    /// `aerie-twinkle`: opacity 0.92 ↔ 0.62 over 11s.
    let twinkles: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        ZStack {
            ForEach(layers.indices, id: \.self) { i in
                TiledDots(dot: layers[i], direction: direction, speed: speed,
                          animated: !reduceMotion)
            }
        }
        .opacity(twinkles ? (dimmed ? 0.62 : 0.92) : 1)
        .onAppear {
            guard twinkles, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
    }
}

private struct TiledDots: View {
    let dot: StarLayer.Dot
    let direction: CGSize
    let speed: CGFloat
    let animated: Bool

    @State private var travelled = false

    var body: some View {
        GeometryReader { geo in
            let dx = direction.width * dot.tile
            let dy = direction.height * dot.tile
            // Oversize by the full travel so no edge is ever exposed, and start
            // the layer shifted back against its direction of travel.
            let padX = abs(dx), padY = abs(dy)
            Canvas { ctx, size in
                var ty: CGFloat = 0
                while ty < size.height {
                    var tx: CGFloat = 0
                    while tx < size.width {
                        let d = dot.size
                        let cx = tx + dot.tile * dot.x
                        let cy = ty + dot.tile * dot.y
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)),
                                 with: .color(dot.color))
                        tx += dot.tile
                    }
                    ty += dot.tile
                }
            }
            .frame(width: geo.size.width + padX, height: geo.size.height + padY)
            .drawingGroup()
            .offset(x: (dx < 0 ? 0 : -padX) + (travelled ? dx : 0),
                    y: (dy < 0 ? 0 : -padY) + (travelled ? dy : 0))
            .onAppear {
                guard animated else { return }
                let duration = Double(hypot(dx, dy) / max(speed, 0.1))
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    travelled = true
                }
            }
        }
    }
}
