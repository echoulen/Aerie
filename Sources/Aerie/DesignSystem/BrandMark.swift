import SwiftUI

/// The Aerie brand mark — a small amber radar-orb on dark glass.
/// Design source: docs/superpowers/design/v2/styles.css `.brand-mark`
///   `radial-gradient(circle at 35% 30%, amber 0%, oklch(0.55 0.13 70) 70%, oklch(0.30 0.06 70) 100%)`
///   `box-shadow: 0 0 12px var(--amber-glow)`
struct BrandMark: View {
    var size: CGFloat = 14

    var body: some View {
        // Off-center radial gradient (highlight at top-left 35% / 30%).
        // The CSS oklch stops at 70% and 100% darken into a deep amber rim.
        let mid = Color(red: 0.62, green: 0.45, blue: 0.18)  // oklch(0.55 0.13 70)
        let rim = Color(red: 0.32, green: 0.23, blue: 0.10)  // oklch(0.30 0.06 70)

        return Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: AerieColor.amber, location: 0.0),
                        .init(color: mid, location: 0.7),
                        .init(color: rim, location: 1.0),
                    ]),
                    center: UnitPoint(x: 0.35, y: 0.30),
                    startRadius: 0,
                    endRadius: size * 0.85
                )
            )
            .frame(width: size, height: size)
            .shadow(color: AerieColor.amberGlow, radius: 6)
    }
}
