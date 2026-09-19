import SwiftUI
import AppKit

/// The deep-space field the hull floats on (MARK III, `styles.css .backdrop`).
/// Everything is slowly adrift:
///   1. three nebula clouds (burnt orange upper-right, violet lower-left, a faint
///      cyan wash at the bottom) swimming against each other,
///   2. a space-2 → space-0 base radial,
///   3. a near starfield — bigger, brighter, twinkling — drifting up-left fastest,
///   4. a far starfield — finer, dimmer — crawling the same way, slower, for parallax,
///   5. three planets — Jupiter, Venus, Uranus — drifting slowest of all,
///   6. film-grain noise.
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
    /// Draw the planets. Screen snapshot tests turn this off so their
    /// baselines don't hinge on the backdrop art.
    var showsPlanets: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                // Nebulae and stars drift on Core Animation (see
                // `BackdropMotion.swift`) — a SwiftUI animation here would
                // re-rasterise the whole backdrop every frame.
                NebulaField(intensity: nebulaIntensity, animated: !reduceMotion)

                if showsStars {
                    Starfield(animated: !reduceMotion)
                }

                if showsPlanets {
                    PlanetField(animated: !reduceMotion)
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
    }
}
