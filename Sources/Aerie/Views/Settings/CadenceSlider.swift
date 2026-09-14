import SwiftUI

/// A labelled slider for picking a polling cadence in seconds.
///
/// Visual contract (MARK III):
/// - Recessed near-black squared track (2pt radius) with the glass hairline.
/// - Hot-gold gradient fill from the start of the track to the knob, glowing.
/// - A bevelled gold key knob (`HudKeyShape`) with a bright rim and gold glow.
/// - Uppercase mono label readout; the value reads in glowing gold mono.
///
/// The slider uses a straight linear mapping over the configured `range`
/// — `AdvancedScreen` narrows the active slider to `15…600s` and the
/// background slider to `60…3600s`, which already biases the lower
/// seconds toward the start of the track without needing a logarithmic
/// curve.
struct CadenceSlider: View {
    @Binding var seconds: TimeInterval
    var range: ClosedRange<TimeInterval> = 15...3600
    var label: String = ""

    init(
        label: String,
        seconds: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval> = 15...3600
    ) {
        self.label = label
        self._seconds = seconds
        self.range = range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .aerieFont(AerieFont.body().weight(.medium))
                    .foregroundStyle(AerieColor.text1)
                Spacer()
                Text(formatted(seconds).uppercased())
                    .aerieFont(AerieFont.code(12).weight(.semibold).monospacedDigit())
                    .tracking(0.6)
                    .foregroundStyle(AerieColor.amber)
                    .shadow(color: AerieColor.amberGlow.opacity(0.45), radius: 6)
            }
            slider
        }
    }

    private var slider: some View {
        GeometryReader { geo in
            let trackHeight: CGFloat = 6
            let knob: CGFloat = 16
            let span = range.upperBound - range.lowerBound
            let clampedSeconds = min(max(seconds, range.lowerBound), range.upperBound)
            let fraction = span > 0
                ? CGFloat((clampedSeconds - range.lowerBound) / span)
                : 0
            let knobX = max(knob / 2, min(geo.size.width - knob / 2, fraction * geo.size.width))

            ZStack(alignment: .leading) {
                // Track — dark translucent groove with the glass hairline,
                // vertically centred in the knob-height row.
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                            .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                    )
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
                // Fill
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(LinearGradient(colors: [AerieColor.amber2, AerieColor.amber],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, knobX), height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .shadow(color: AerieColor.amberGlow.opacity(0.5), radius: 5)
                // Knob — a bevelled gold key, centred on the track line.
                HudKeyShape(cut: 4)
                    .fill(LinearGradient(colors: [AerieColor.amberFillTop, AerieColor.amberFillBot],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(HudKeyShape(cut: 4).strokeBorder(AerieColor.amberCtaLine, lineWidth: 1))
                    .frame(width: knob - 4, height: knob)
                    .position(x: knobX, y: knob / 2)
                    .shadow(color: AerieColor.amberGlow.opacity(0.6), radius: 6)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let clamped = max(0, min(geo.size.width, value.location.x))
                                let width = max(1, geo.size.width)
                                let frac = clamped / width
                                let next = range.lowerBound + Double(frac) * span
                                seconds = round(next)
                            }
                    )
            }
            .frame(height: knob)
        }
        .frame(height: 16)
    }

    private func formatted(_ s: TimeInterval) -> String {
        if s < 60 { return "\(Int(s))s" }
        let mins = s / 60
        if mins.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(mins)) min"
        } else {
            return String(format: "%.1f min", mins)
        }
    }
}
