import SwiftUI
import AppKit

/// Settings → About screen. Shows the Aerie brand, version + build SHA, and
/// a link to the GitHub repository. Versions are sourced from the bundled
/// `Info.plist`; the build SHA is read from a custom `GitCommitSHA` key that
/// is set by the release pipeline.
///
/// MARK III: the icon sits inside gold `.hud-corners` brackets, the wordmark
/// carries the `.section-title` gold glow, version/build read as mono
/// telemetry, and the repo link is a bevelled HUD key.
struct AboutScreen: View {
    /// Production callers omit these; tests inject deterministic values.
    var version: String = AboutScreen.defaultVersion
    var buildSHA: String = AboutScreen.defaultBuildSHA
    var githubURL: URL = URL(string: "https://github.com/echoulen/Aerie")!

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            appIcon
                .padding(18)
                .overlay(HudCorners(length: 16))
                .padding(.bottom, 4)
            VStack(spacing: 6) {
                SectionEyebrow(text: "About")
                Text("Aerie")
                    .aerieFont(AerieFont.display())
                    .tracking(1.5)
                    .foregroundStyle(AerieColor.text1)
                    .shadow(color: AerieColor.amber.opacity(0.30), radius: 16)
            }
            VStack(spacing: 6) {
                Text("version \(version)".uppercased())
                    .aerieFont(AerieFont.code(11.5).weight(.medium))
                    .tracking(1.4)
                    .foregroundStyle(AerieColor.amber)
                Text(buildSHA)
                    .aerieFont(AerieFont.code(11))
                    .tracking(0.6)
                    .foregroundStyle(AerieColor.text3)
                HudRail()
                    .frame(width: 160)
                    .padding(.top, 4)
            }
            Button {
                NSWorkspace.shared.open(githubURL)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(AerieColor.amber)
                    Text("github.com/echoulen/Aerie")
                }
            }
            .buttonStyle(.hud(.standard))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AerieMetric.pagePadding)
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
}
