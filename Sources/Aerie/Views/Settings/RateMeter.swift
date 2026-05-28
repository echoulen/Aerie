import SwiftUI

/// A horizontal meter rendering "remaining / limit" for a GitHub API
/// account's rate limit.
///
/// Color thresholds (per Phase 14 spec):
/// - `> 90%` remaining: `AerieColor.ok` (green)
/// - `30–90%` remaining: `AerieColor.amber`
/// - `< 30%` remaining: `AerieColor.err` (red)
struct RateMeter: View {
    let remaining: Int
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(remaining) / \(limit)")
                    .font(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text2)
                Spacer()
                Text("\(percentage)% remaining")
                    .font(AerieFont.eyebrow())
                    .foregroundStyle(color)
            }
            bar
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
                Capsule()
                    .fill(AerieColor.glass1)
                    .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
                    .frame(height: 6)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(percentage) / 100, height: 6)
            }
        }
        .frame(height: 6)
    }
}
