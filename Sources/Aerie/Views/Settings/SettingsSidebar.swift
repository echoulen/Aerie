import SwiftUI

/// The Settings navigation rail.
///
/// Visual contract: `src/v2/settings.jsx` `SettingsSidebar` — 220 wide, a
/// glass-line right border, a gold `.section-eyebrow` "SETTINGS", and rows at
/// 9/14 padding with a 2pt radius. The selected row is glass-3 + a 1px
/// glass-line border with a text-1 label and a gold glyph; unselected rows are
/// text-2 with a text-3 glyph. Counts are mono 11 text-4; AI Model shows the
/// model name in mono 10 gold; MCP shows a green "●" while the server runs.
/// About is pinned to the bottom.
struct SettingsSidebar: View {
    @Binding var selection: SettingsRoute
    /// Whether the MCP server is currently running. Drives the MCP row's
    /// status dot (green = running, dim = stopped).
    var mcpRunning: Bool = false
    /// Live counts shown on the right of the Accounts / Repositories rows,
    /// matching the design. `nil` hides the count (e.g. in isolation tests).
    var accountsCount: Int? = nil
    var repositoriesCount: Int? = nil
    /// Short name of the selected Claude model, shown on the AI Model row.
    /// `nil` hides it.
    var aiModelName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow(text: "Settings")
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 10)

            ForEach(routesAbove, id: \.self) { route in
                row(route)
            }
            Spacer()
            row(.about)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(width: 220)
        .background(
            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(width: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        )
    }

    private var routesAbove: [SettingsRoute] {
        SettingsRoute.allCases.filter { $0 != .about }
    }

    private func iconKind(for route: SettingsRoute) -> SidebarIcon.Kind {
        switch route {
        case .accounts:     return .key
        case .repositories: return .folder
        case .pullRequests: return .pullRequest
        case .aiModel:      return .cpu
        case .mcp:          return .plug
        case .appearance:   return .appearance
        case .advanced:     return .sliders
        case .about:        return .info
        }
    }

    private func count(for route: SettingsRoute) -> Int? {
        switch route {
        case .accounts:     return accountsCount
        case .repositories: return repositoriesCount
        default:            return nil
        }
    }

    @ViewBuilder
    private func row(_ route: SettingsRoute) -> some View {
        let isSelected = selection == route
        Button(action: { selection = route }) {
            HStack(spacing: 11) {
                SidebarIcon(
                    kind: iconKind(for: route),
                    color: isSelected ? AerieColor.amber : AerieColor.text3
                )
                .frame(width: 18)
                Text(route.displayName)
                    .aerieFont(AerieFont.custom(.sans, size: 13))
                    .foregroundStyle(isSelected ? AerieColor.text1 : AerieColor.text2)
                Spacer(minLength: 8)
                trailingAccessory(route)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(isSelected ? AerieColor.glass3 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(isSelected ? AerieColor.glassLine : Color.clear, lineWidth: 1)
            )
            // Make the whole row tappable, not just the icon/text glyphs.
            // Plain `Button` style only hits opaque content, so MCP — whose
            // text is shorter than the row — was hard to click anywhere
            // outside the word itself.
            .contentShape(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trailingAccessory(_ route: SettingsRoute) -> some View {
        if route == .mcp {
            // Always show an indicator so the row's MCP state is legible:
            // green "●" when the server is running, dim otherwise.
            Text("●")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(mcpRunning ? AerieColor.ok : AerieColor.text4)
        } else if route == .aiModel, let aiModelName {
            Text(aiModelName)
                .aerieFont(AerieFont.code(10))
                .foregroundStyle(AerieColor.amber)
                .lineLimit(1)
        } else if let n = count(for: route) {
            Text("\(n)")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
        }
    }
}
