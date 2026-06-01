import SwiftUI

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
                // Base — slate centre falling off to near-black at the corners.
                RadialGradient(
                    colors: [baseCenter, baseEdge],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(w, h) * 0.8
                )

                // Warm glow, upper-right (fades to transparent at ~60%).
                RadialGradient(
                    colors: [warm.opacity(0.32), warm.opacity(0)],
                    center: UnitPoint(x: 0.80, y: 0.12),
                    startRadius: 0,
                    endRadius: w * 0.55
                )

                // Violet glow, lower-left.
                RadialGradient(
                    colors: [violet.opacity(0.28), violet.opacity(0)],
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
            }
        }
        .ignoresSafeArea()
    }
}
