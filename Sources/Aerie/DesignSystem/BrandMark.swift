import SwiftUI

/// The Aerie brand mark — a white-hot gold orb with a breathing glow.
/// Design source: `styles.css` `.brand-mark`
///   `radial-gradient(#fff 0%, amber 38%, oklch(0.55 0.15 60) 72%, oklch(0.26 0.06 60) 100%)`
///   `box-shadow: 0 0 14px var(--amber-glow)`, pulsing 10 → 20px over 3.2s.
///
/// Drawn on Core Animation (`BrandMarkView`): a shadow radius that breathes
/// was the most expensive thing to animate in SwiftUI — a fresh blur every
/// frame, forever, in the titlebar of every window.
struct BrandMark: View {
    var size: CGFloat = 14
    /// Breathe the glow. Off for static contexts (e.g. snapshot tests).
    var pulses: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrandMarkLayer(animated: pulses && !reduceMotion)
            .frame(width: size, height: size)
    }
}
