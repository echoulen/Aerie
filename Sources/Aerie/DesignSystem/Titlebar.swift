import SwiftUI

/// Custom titlebar (`AerieMetric.titlebarHeight`) that sits flush under the
/// native (transparent) title bar. The native macOS traffic lights stay at
/// top-left; this view draws the centred MARK III brand cluster — the gold
/// `BrandMark` orb plus a letter-spaced, uppercase title (`styles.css .brand`)
/// — over a faint warm wash, with a gold hairline along the bottom that fades
/// out and slants away before the right end (`.titlebar::after`).
///
/// The title text is the only per-window difference: the main window shows
/// "Aerie", the Settings window "Aerie · Settings".
///
/// Narrower main windows swap the centre (`compact.jsx`): `center` replaces the
/// brand cluster (the medium tier puts the tab switcher there), and
/// `markOnly` drops the wordmark, leaving just the orb (compact tier).
struct Titlebar<Center: View>: View {
    var title: String = "Aerie"
    var markOnly: Bool = false
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            if Center.self != EmptyView.self {
                center()
            } else {
                HStack(spacing: 10) {
                    BrandMark(size: markOnly ? 11 : 14)
                    if !markOnly {
                        Text(title.uppercased())
                            .aerieFont(AerieFont.custom(.sans, size: 11).weight(.semibold))
                            .tracking(3.3)                   // 0.30em @ 11pt
                            .foregroundStyle(AerieColor.text2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AerieMetric.titlebarHeight)
        .background(
            LinearGradient(colors: [Color(red: 1, green: 198/255, blue: 130/255).opacity(0.07), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) { TitlebarHairline() }
    }
}

extension Titlebar where Center == EmptyView {
    init(title: String = "Aerie", markOnly: Bool = false) {
        self.init(title: title, markOnly: markOnly, center: { EmptyView() })
    }
}

/// `.titlebar::after` — gold hairline from 34pt in, fading at both ends, that
/// breaks into a short 42° slant ~118pt from the right and continues as a
/// dimmer glass line one step higher.
private struct TitlebarHairline: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mainEnd = max(34, w - 150)
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: AerieColor.amberLine, location: 0.08),
                    .init(color: AerieColor.amberLine, location: 0.62),
                    .init(color: .clear, location: 0.78),
                ], startPoint: .leading, endPoint: .trailing)
                .frame(width: mainEnd - 34, height: 1)
                .offset(x: 34, y: h - 1)

                Path { p in
                    p.move(to: CGPoint(x: w - 134, y: h - 0.5))
                    p.addLine(to: CGPoint(x: w - 118, y: 0.5))
                }
                .stroke(AerieColor.amberLine, lineWidth: 1)

                LinearGradient(colors: [AerieColor.glassLine, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 108, height: 1)
                    .offset(x: w - 108, y: 0)
            }
        }
        .frame(height: 14)
        .allowsHitTesting(false)
    }
}
