import SwiftUI

/// "remaining / limit" readout + meter for a GitHub API account's rate limit.
///
/// Visual contract (`advanced.jsx` RATE LIMIT column): a 30pt medium text-1
/// count with a mono 13 text-3 "/ limit", a 4pt capsule meter (black/0.32
/// track, glass hairline) whose fill glows in its band colour, and an 11.5
/// text-4 "resets in N min" line when the reset time is known.
///
/// Color thresholds (per Phase 14 spec):
/// - `> 90%` remaining: `AerieColor.ok` (green)
/// - `30–90%` remaining: `AerieColor.amber` (gold)
/// - `< 30%` remaining: `AerieColor.err` (crimson)
struct RateMeter: View {
    let remaining: Int
    let limit: Int
    /// Unix epoch at which the window resets. `nil` hides the reset line.
    var resetEpoch: TimeInterval? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(remaining.formatted())
                    .aerieFont(AerieFont.custom(.sans, size: 30).weight(.medium).monospacedDigit())
                    .foregroundStyle(AerieColor.text1)
                Text("/ \(limit.formatted())")
                    .aerieFont(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text3)
            }
            bar
            if let resetLabel {
                Text(resetLabel)
                    .aerieFont(AerieFont.custom(.sans, size: 11.5))
                    .foregroundStyle(AerieColor.text4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remaining) of \(limit) requests remaining, \(percentage) percent")
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

    private var resetLabel: String? {
        guard let resetEpoch else { return nil }
        let mins = max(0, Int(((resetEpoch - Date().timeIntervalSince1970) / 60).rounded(.up)))
        return "resets in \(mins) min"
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.32))
                    .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(percentage) / 100)
                    .shadow(color: color.opacity(0.8), radius: 4)
            }
        }
        .frame(height: 4)
    }
}
