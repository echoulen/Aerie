import SwiftUI

/// Top-right titlebar pulse: an arc-cyan dot + monospace countdown to the next
/// polling tick. A polling tick is live energy, so this is one of the few
/// places MARK III lets arc cyan glow; the dot breathes while the scheduler
/// runs. Paused state (scheduler stopped, e.g. app inactive) renders a dim,
/// still dot + "PAUSED" label.
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
                .fill(isLive ? AerieColor.arc : AerieColor.text4)
                .frame(width: 6, height: 6)
                .shadow(color: isLive ? AerieColor.arcGlow : .clear, radius: isLive ? 4 : 0)
                .opacity(isLive && pulsing ? 0.55 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulsing = true
                    }
                }
            Text(label)
                .aerieFont(AerieFont.eyebrow())
                .tracking(1.8)
                .foregroundStyle(AerieColor.text3)
                .monospacedDigit()
        }
    }

    private var label: String {
        guard let s = nextTickInSeconds else { return "PAUSED" }
        return "LIVE · \(s)s"
    }
}
