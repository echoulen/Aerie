import SwiftUI

/// Compact `↑ahead ↓behind ⤒unpushed` indicator. Renders only the non-zero
/// clusters; if everything is zero, renders nothing (caller can rely on
/// `EmptyView` semantics for layout).
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` `Delta(...)`.
struct DeltaView: View {
    let ahead: Int
    let behind: Int
    let unpushed: Int

    var body: some View {
        if ahead == 0 && behind == 0 && unpushed == 0 {
            EmptyView()
        } else {
            HStack(spacing: 14) {
                if ahead > 0 {
                    cluster(symbol: "↑", value: ahead, color: AerieColor.text1)
                }
                if behind > 0 {
                    cluster(symbol: "↓", value: behind, color: AerieColor.text1)
                }
                if unpushed > 0 {
                    cluster(symbol: "⤒", value: unpushed, color: AerieColor.amber)
                }
            }
        }
    }

    @ViewBuilder
    private func cluster(symbol: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(symbol)
                .font(AerieFont.code(12))
                .foregroundStyle(color)
            Text("\(value)")
                .font(AerieFont.code(12).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
