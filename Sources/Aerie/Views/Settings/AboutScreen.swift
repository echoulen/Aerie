import SwiftUI
import AppKit

/// Settings → About screen. Shows the Aerie brand, version + build SHA, and
/// a link to the GitHub repository. Versions are sourced from the bundled
/// `Info.plist`; the build SHA is read from a custom `GitCommitSHA` key that
/// is set by the release pipeline.
///
/// Visual contract: `src/v2/system.jsx` `SettingsAbout` — a centred, clipped
/// column over three concentric rings (glass 520, gold 380, a dashed 250 that
/// slowly rotates), the app icon with a gold drop-shadow, a tracked "AERIE"
/// wordmark with a gold glow, the version + mono sha/date, the repo link as a
/// gold pill, and a `.hud-note` build line.
struct AboutScreen: View {
    /// Production callers omit these; tests inject deterministic values.
    var version: String = AboutScreen.defaultVersion
    var buildSHA: String = AboutScreen.defaultBuildSHA
    var buildDate: String? = AboutScreen.defaultBuildDate
    var githubURL: URL = URL(string: "https://github.com/echoulen/Aerie")!

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringAngle: Double = 0

    var body: some View {
        ZStack {
            rings
            VStack(spacing: 18) {
                appIcon
                    .shadow(color: AerieColor.amber.opacity(0.45), radius: 20)
                Text("AERIE")
                    .aerieFont(AerieFont.custom(.sans, size: 38).weight(.bold))
                    .tracking(8.4)                       // 0.22em @ 38pt
                    .foregroundStyle(AerieColor.text1)
                    .shadow(color: AerieColor.amber.opacity(0.45), radius: 10)
                VStack(spacing: 5) {
                    Text("VERSION \(version)")
                        .aerieFont(AerieFont.custom(.sans, size: 13))
                        .tracking(1.3)                   // 0.10em @ 13pt
                        .foregroundStyle(AerieColor.text2)
                    Text([buildSHA, buildDate].compactMap { $0 }.joined(separator: " · "))
                        .aerieFont(AerieFont.code(11))
                        .foregroundStyle(AerieColor.text3)
                }
                Button {
                    NSWorkspace.shared.open(githubURL)
                } label: {
                    Text("github.com/echoulen/Aerie ↗")
                        .aerieFont(AerieFont.custom(.sans, size: 11.5).weight(.semibold))
                        .tracking(1.15)
                        .foregroundStyle(AerieColor.amber)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                                .fill(AerieColor.amberSoft)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                                .strokeBorder(AerieColor.amberLine, lineWidth: 1)
                        )
                        .shadow(color: AerieColor.amberGlow.opacity(0.35), radius: 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HudNote(text: "swiftpm · macos 14+")
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .padding(AerieMetric.pagePadding)
    }

    /// Concentric backdrop rings; the dashed inner ring turns once every 70s
    /// (static when Reduce Motion is on).
    private var rings: some View {
        ZStack {
            Circle()
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                .frame(width: 520, height: 520)
                .opacity(0.6)
            Circle()
                .strokeBorder(AerieColor.amberLine, lineWidth: 1)
                .frame(width: 380, height: 380)
                .opacity(0.35)
            Circle()
                .strokeBorder(AerieColor.glassLine2, style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                .frame(width: 250, height: 250)
                .opacity(0.5)
                .rotationEffect(.degrees(ringAngle))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 70).repeatForever(autoreverses: false)) { ringAngle = 360 }
        }
    }

    /// The real macOS app icon — the sodium-amber radar mark on dark glass
    /// (design `icon.jsx`). Loaded from the bundled PNG so the squircle and
    /// inner artwork are pixel-perfect rather than re-approximated.
    @ViewBuilder
    private var appIcon: some View {
        let size: CGFloat = 112
        if let url = Bundle.aerieResources.url(forResource: "app-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            BrandMark(size: size)
        }
    }

    private static var defaultVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static var defaultBuildSHA: String {
        Bundle.main.infoDictionary?["GitCommitSHA"] as? String ?? "dev"
    }

    private static var defaultBuildDate: String? {
        Bundle.main.infoDictionary?["GitCommitDate"] as? String
    }
}
