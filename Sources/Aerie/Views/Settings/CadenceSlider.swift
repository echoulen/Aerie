import SwiftUI

/// A labelled slider for picking a polling cadence in seconds.
///
/// Visual contract (`advanced.jsx` cadence row):
/// - Label 14 medium text-1 (optional 12 text-3 hint), value mono 22 medium
///   text-1 on the right; the slider sits 9pt below.
/// - Track 6pt tall, fully rounded, black/0.32 with the glass hairline.
/// - Fill fully rounded, gold gradient `amberFillBot → amberFillTop`
///   left→right, with a 10pt gold/0.4 glow.
/// - Knob: 16pt white circle, 1px black/0.10 border, `0 1 4 black/0.6` shadow.
/// - Min / max labels mono 10.5 text-4, 6pt below the track.
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
    var hint: String? = nil

    init(
        label: String,
        hint: String? = nil,
        seconds: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval> = 15...3600
    ) {
        self.label = label
        self.hint = hint
        self._seconds = seconds
        self.range = range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .aerieFont(AerieFont.custom(.sans, size: 14).weight(.medium))
                        .foregroundStyle(AerieColor.text1)
                    if let hint {
                        Text(hint)
                            .aerieFont(AerieFont.small())
                            .foregroundStyle(AerieColor.text3)
                    }
                }
                Spacer()
                Text(formatted(seconds))
                    .aerieFont(AerieFont.custom(.mono, size: 22).weight(.medium).monospacedDigit())
                    .foregroundStyle(AerieColor.text1)
            }
            slider
                .padding(.top, 9)
            HStack {
                Text(formatted(range.lowerBound))
                Spacer()
                Text(formatted(range.upperBound))
            }
            .aerieFont(AerieFont.code(10.5))
            .foregroundStyle(AerieColor.text4)
            .padding(.top, 6)
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
                Capsule()
                    .fill(Color.black.opacity(0.32))
                    .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
                // Fill
                Capsule()
                    .fill(LinearGradient(colors: [AerieColor.amberFillBot, AerieColor.amberFillTop],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, knobX), height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .shadow(color: AerieColor.amber.opacity(0.4), radius: 5)
                // Knob — white, centred on the track line.
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 1))
                    .frame(width: knob, height: knob)
                    .position(x: knobX, y: knob / 2)
                    .shadow(color: Color.black.opacity(0.6), radius: 2, y: 1)
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
