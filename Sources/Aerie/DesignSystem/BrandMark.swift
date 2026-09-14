import SwiftUI

/// The Aerie brand mark — a white-hot gold orb with a breathing glow.
/// Design source: `styles.css` `.brand-mark`
///   `radial-gradient(#fff 0%, amber 38%, oklch(0.55 0.15 60) 72%, oklch(0.26 0.06 60) 100%)`
///   `box-shadow: 0 0 14px var(--amber-glow)`, pulsing 10 → 20px over 3.2s.
struct BrandMark: View {
    var size: CGFloat = 14
    /// Breathe the glow. Off for static contexts (e.g. snapshot tests).
    var pulses: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    private let mid = Color(red: 0.683, green: 0.339, blue: 0.0)   // oklch(0.55 0.15 60)
    private let rim = Color(red: 0.221, green: 0.108, blue: 0.003) // oklch(0.26 0.06 60)

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: AerieColor.amber, location: 0.38),
                        .init(color: mid, location: 0.72),
                        .init(color: rim, location: 1.0),
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .shadow(color: AerieColor.amberGlow, radius: bright ? 10 : 5)
            .onAppear {
                guard pulses, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}
