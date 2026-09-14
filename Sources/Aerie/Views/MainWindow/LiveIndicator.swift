import SwiftUI

/// Top-right titlebar pulse: a green dot + monospace countdown to the next
/// polling tick. Mirrors the design's `dot ok live` (`system.jsx`): the 6pt dot
/// breathes (opacity 1 → .55, scale 1 → .82 over 1.8s) while the scheduler
/// runs. Paused state (scheduler stopped, e.g. app inactive) renders a still,
/// muted dot + "PAUSED" label.
///
/// Driven by `AppViewModel.nextTickInSeconds`. Phase 8 leaves the binding to
/// the real scheduler for a later phase — tests pass values directly.
struct LiveIndicator: View {
    /// `nil` when scheduler is paused (e.g. app inactive).
    let nextTickInSeconds: Int?

    @State private var pulsing = false

    private var isLive: Bool { nextTickInSeconds != nil }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isLive ? AerieColor.ok : AerieColor.text4)
                .frame(width: 6, height: 6)
                .shadow(color: isLive ? AerieColor.ok.opacity(0.85) : .clear, radius: isLive ? 5 : 0)
                .scaleEffect(isLive && pulsing ? 0.82 : 1)
                .opacity(isLive && pulsing ? 0.55 : 1)
                .onAppear {
                    // One half-cycle each way → a full 1.8s breath.
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulsing = true
                    }
                }
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
