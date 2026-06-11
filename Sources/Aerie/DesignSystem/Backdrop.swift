import SwiftUI
import AppKit

/// The aurora the glass window sits on. Faithful to the v2 design's three
/// stacked radial gradients (styles.css `.backdrop`):
///   1. a burnt sodium-amber glow in the upper-right,
///   2. a muted violet glow in the lower-left,
///   3. a dark slate→near-black base radial.
///
/// The earlier implementation used a bright amber over a pure-blue glow; the
/// two blended through the dark middle into a greenish cast on the Settings
/// cards. Matching the design's burnt-orange (hue 60) + violet (hue 290) keeps
/// the blend warm and removes the green.
struct Backdrop: View {
    // --- Half-transparent "liquid glass" knobs (tune while validating) ---
    //
    // The window is made transparent in `AerieWindowChrome`; the behind-window
    // blur below frosts whatever sits behind Aerie, and `baseOpacity` controls
    // how much dark aurora tint sits on top of that glass.
    //
    //   baseOpacity = 1.0 → original solid backdrop, no desktop shows through.
    //   baseOpacity ↓     → more of the frosted desktop bleeds in (more glassy).
    var baseOpacity: Double = 0.8
    // When true, a behind-window `NSVisualEffectView` *frosts* (blurs) whatever
    // is behind the window — milky glass, NOT a clear see-through. When false,
    // no blur: the transparent window shows the desktop crisply, tinted only by
    // `baseOpacity` + `dim`. This is the "real transparency, not frosted glass"
    // switch — the blur is why lowering `baseOpacity` only brightened the haze.
    var frostedGlass: Bool = true
    // Material used only when `frostedGlass` is true. `.hudWindow` is dark;
    // `.underWindowBackground` lighter, `.fullScreenUI` darker.
    var glassMaterial: NSVisualEffectView.Material = .hudWindow
    // How strong the frost is: the blur layer's opacity. 1 = full milky blur;
    // lower lets the crisp desktop bleed through, giving "just a little" blur.
    var blurStrength: Double = 0.62
    // Multiplier on the warm/violet aurora glows — higher = more saturated,
    // colourful background. 1.0 = the original muted glows.
    var auroraIntensity: Double = 1.6
    // Flat black veil over everything (glass, aurora, the desktop showing
    // through) — raise to darken the whole window *without* reducing how much
    // shows through. 0 = no extra darkening.
    var dim: Double = 0.18

    // oklch(0.55 0.13 60) — burnt sodium amber
    private let warm = Color(red: 0.655, green: 0.359, blue: 0.0)
    // oklch(0.42 0.13 290) — muted violet
    private let violet = Color(red: 0.307, green: 0.235, blue: 0.555)
    // base radial: oklch(0.20 0.02 250) → oklch(0.10 0.01 270)
    private let baseCenter = Color(red: 0.059, green: 0.089, blue: 0.121)
    private let baseEdge = Color(red: 0.010, green: 0.013, blue: 0.022)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Behind-window glass — blurs whatever sits behind the Aerie
                // window (desktop, other apps). This *is* the "frosted, not
                // see-through" look; disabled by default for crisp transparency.
                if frostedGlass {
                    VisualEffectBlur(material: glassMaterial, blendingMode: .behindWindow)
                        .opacity(blurStrength)
                }

                // Base — slate centre falling off to near-black at the corners.
                // Half-transparent (was solid) so the glass above shows through.
                RadialGradient(
                    colors: [baseCenter, baseEdge],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(w, h) * 0.8
                )
                .opacity(baseOpacity)

                // Warm glow, upper-right (fades to transparent at ~60%).
                RadialGradient(
                    colors: [warm.opacity(min(0.32 * auroraIntensity, 1)), warm.opacity(0)],
                    center: UnitPoint(x: 0.80, y: 0.12),
                    startRadius: 0,
                    endRadius: w * 0.55
                )

                // Violet glow, lower-left.
                RadialGradient(
                    colors: [violet.opacity(min(0.28 * auroraIntensity, 1)), violet.opacity(0)],
                    center: UnitPoint(x: 0.18, y: 0.88),
                    startRadius: 0,
                    endRadius: w * 0.55
                )

                // Noise overlay
                Image("noise", bundle: .aerieResources)
                    .resizable()
                    .interpolation(.none)
                    .blendMode(.overlay)
                    .opacity(0.045)

                // Global darkening veil (see `dim`). Sits above everything so it
                // dims the glass, aurora, and the desktop bleeding through alike.
                Color.black.opacity(dim)
            }
        }
        .ignoresSafeArea()
    }
}
