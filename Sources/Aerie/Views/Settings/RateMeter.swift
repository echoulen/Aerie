import SwiftUI

/// A horizontal meter rendering "remaining / limit" for a GitHub API
/// account's rate limit.
///
/// MARK III: a squared 4pt telemetry bar in a recessed well, the fill glowing
/// in its band colour, with a `.hud-rail` tick ruler beneath and uppercase
/// mono readouts.
///
/// Color thresholds (per Phase 14 spec):
/// - `> 90%` remaining: `AerieColor.ok` (green)
/// - `30–90%` remaining: `AerieColor.amber` (gold)
/// - `< 30%` remaining: `AerieColor.err` (crimson)
struct RateMeter: View {
    let remaining: Int
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(remaining) / \(limit)")
                    .aerieFont(AerieFont.code(11).monospacedDigit())
                    .foregroundStyle(AerieColor.text2)
                Spacer()
                Text("\(percentage)% remaining".uppercased())
                    .aerieFont(AerieFont.eyebrow())
                    .tracking(1.4)
                    .foregroundStyle(color)
            }
            bar
            HudRail(spacing: 10, height: 3)
        }
    }

    private var percentage: Int {
        guard limit > 0 else { return 0 }
        return Int(Double(remaining) / Double(limit) * 100)
    }

    private var color: Color {
        let p = percentage
        if p > 90 { return AerieColor.ok }
        if p >= 30 { return AerieColor.amber }
        return AerieColor.err
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(Color.black.opacity(0.36))
                    .overlay(
                        RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                            .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                    )
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, geo.size.width * CGFloat(percentage) / 100 - 2), height: 4)
                    .padding(.leading, 1)
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
        }
        .frame(height: 6)
    }
}
