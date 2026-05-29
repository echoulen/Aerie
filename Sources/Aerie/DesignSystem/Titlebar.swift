import SwiftUI

/// Custom titlebar (`AerieMetric.titlebarHeight`, 32 pt) that sits flush under
/// the native (transparent) title bar. The native macOS traffic lights stay at
/// top-left; this view draws a horizontally-centred brand cluster — the amber
/// `BrandMark` orb plus a title — exactly like the v2 design (`styles.css
/// .brand`, centred via `left: 50%`).
///
/// The 32 pt height matches the native title-bar band so the vertically-centred
/// brand cluster lands at 16 pt — the measured centre of the traffic lights —
/// leaving "Aerie" level with the system window controls.
///
/// The title text is the only per-window difference: the main window shows
/// "Aerie", the Settings window "Aerie · Settings".
struct Titlebar: View {
    var title: String = "Aerie"

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                BrandMark(size: 14)
                Text(title)
                    .aerieFont(AerieFont.body().weight(.medium))
                    .foregroundStyle(AerieColor.text2)
                    .tracking(0.13)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AerieMetric.titlebarHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(height: 1)
        }
    }
}
