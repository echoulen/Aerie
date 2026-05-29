import SwiftUI
import AppKit

/// Settings → About screen. Shows the Aerie brand, version + build SHA, and
/// a link to the GitHub repository. Versions are sourced from the bundled
/// `Info.plist`; the build SHA is read from a custom `GitCommitSHA` key that
/// is set by the release pipeline.
struct AboutScreen: View {
    /// Production callers omit these; tests inject deterministic values.
    var version: String = AboutScreen.defaultVersion
    var buildSHA: String = AboutScreen.defaultBuildSHA
    var githubURL: URL = URL(string: "https://github.com/echoulen/Aerie")!

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            appIcon
                .padding(.bottom, 8)
            Text("Aerie")
                .aerieFont(AerieFont.display())
                .foregroundStyle(AerieColor.text1)
            VStack(spacing: 4) {
                Text("version \(version)")
                    .aerieFont(AerieFont.small())
                    .foregroundStyle(AerieColor.text2)
                Text(buildSHA)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text3)
            }
            Button {
                NSWorkspace.shared.open(githubURL)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text("github.com/echoulen/Aerie")
                }
                .aerieFont(AerieFont.small().weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(AerieColor.amber)
                .background(Capsule().fill(AerieColor.amberSoft))
                .overlay(Capsule().strokeBorder(AerieColor.amberLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
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
        if let url = Bundle.module.url(forResource: "app-icon", withExtension: "png"),
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
