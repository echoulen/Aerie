import SwiftUI

/// Top-right titlebar pulse: a green dot + monospace countdown to the next
/// polling tick. Paused state (scheduler stopped, e.g. app inactive) renders
/// a dim dot + "PAUSED" label.
///
/// Driven by `AppViewModel.nextTickInSeconds`. Phase 8 leaves the binding to
/// the real scheduler for a later phase — tests pass values directly.
struct LiveIndicator: View {
    /// `nil` when scheduler is paused (e.g. app inactive).
    let nextTickInSeconds: Int?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(nextTickInSeconds == nil ? AerieColor.text4 : AerieColor.ok)
                .frame(width: 6, height: 6)
                .shadow(
                    color: (nextTickInSeconds == nil ? .clear : AerieColor.ok.opacity(0.6)),
                    radius: 3
                )
            Text(label)
                .aerieFont(AerieFont.eyebrow())
                .foregroundStyle(AerieColor.text3)
                .monospacedDigit()
        }
    }

    private var label: String {
        guard let s = nextTickInSeconds else { return "PAUSED" }
        return "LIVE · \(s)s"
    }
}
