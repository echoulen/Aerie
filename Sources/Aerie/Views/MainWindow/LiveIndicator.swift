import SwiftUI

/// Top-right titlebar pulse: a green dot + monospace countdown to the next
/// polling tick. Mirrors the design's `dot ok live` (`system.jsx`): the 6pt dot
/// breathes (opacity 1 → .55, scale 1 → .82 over 1.8s) while the scheduler
/// runs. Paused state (scheduler stopped, e.g. app inactive) renders a still,
/// muted dot + "PAUSED" label.
///
/// The breath runs on Core Animation (`BreathingDot`), so the countdown text
/// is the only thing SwiftUI re-renders — once a second.
///
/// Driven by `AppViewModel.nextTickInSeconds`. Phase 8 leaves the binding to
/// the real scheduler for a later phase — tests pass values directly.
struct LiveIndicator: View {
    /// `nil` when scheduler is paused (e.g. app inactive).
    let nextTickInSeconds: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool { nextTickInSeconds != nil }

    var body: some View {
        HStack(spacing: 8) {
            BreathingDot(
                style: .init(
                    color: isLive ? AerieColor.ok : AerieColor.text4,
                    glow: isLive ? AerieColor.ok.opacity(0.85) : nil,
                    glowRadius: 5, period: 1.8, minOpacity: 0.55, minScale: 0.82),
                animated: isLive && !reduceMotion)
                .frame(width: 6, height: 6)
            Text(label)
                .aerieFont(AerieFont.code(10))
                .tracking(2.2) // 0.22em @ 10px
                .foregroundStyle(AerieColor.text3)
                .monospacedDigit()
        }
    }

    private var label: String {
        guard let s = nextTickInSeconds else { return "PAUSED" }
        return "LIVE · \(s)S"
    }
}
