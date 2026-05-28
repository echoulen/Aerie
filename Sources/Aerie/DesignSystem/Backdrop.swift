import SwiftUI

struct Backdrop: View {
    var body: some View {
        ZStack {
            // Base
            LinearGradient(colors: [AerieColor.backdrop1, AerieColor.backdrop2],
                           startPoint: .top, endPoint: .bottom)

            // Warm amber upper-right
            RadialGradient(
                colors: [AerieColor.amber.opacity(0.20), .clear],
                center: UnitPoint(x: 0.8, y: 0.12),
                startRadius: 0, endRadius: 480
            )
            .blur(radius: 40)

            // Cool blue lower-left
            RadialGradient(
                colors: [Color(red: 0.20, green: 0.25, blue: 0.55).opacity(0.20), .clear],
                center: UnitPoint(x: 0.18, y: 0.88),
                startRadius: 0, endRadius: 440
            )
            .blur(radius: 40)

            // Noise overlay
            Image("noise", bundle: .module)
                .resizable()
                .interpolation(.none)
                .blendMode(.overlay)
                .opacity(0.045)
        }
        .ignoresSafeArea()
    }
}
