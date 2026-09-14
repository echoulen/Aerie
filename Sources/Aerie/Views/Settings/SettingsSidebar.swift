import SwiftUI

/// The Settings navigation rail.
///
/// MARK III treatment (`settings.jsx` sidebar + `styles.css`): a gold mono
/// section eyebrow, rows in Chakra Petch, and a selected row lit in gold — a
/// glowing 2pt gold strut on the leading edge, a gold wash fading right, a
/// gold glyph and a gold count. The MCP row's status dot is arc cyan while the
/// server is running (live energy) and dim otherwise.
struct SettingsSidebar: View {
    @Binding var selection: SettingsRoute
    /// Whether the MCP server is currently running. Drives the colour of the
    /// MCP row's status dot (arc cyan = running, dim = stopped).
    var mcpRunning: Bool = false
    /// Live counts shown on the right of the Accounts / Repositories rows,
    /// matching the design. `nil` hides the count (e.g. in isolation tests).
    var accountsCount: Int? = nil
    var repositoriesCount: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionEyebrow(text: "Settings")
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 12)

            ForEach(routesAbove, id: \.self) { route in
                row(route)
            }
            Spacer()
            HudRail()
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            row(.about)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(width: 220)
        .background(
            Rectangle()
                .fill(AerieColor.glass1)
                .overlay(
                    // Trailing divider — a gold-lit hairline fading toward the foot.
                    LinearGradient(colors: [AerieColor.amberLine, AerieColor.glassLine, AerieColor.glassLine],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: 1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                )
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
                .shadow(color: isSelected ? AerieColor.amberGlow.opacity(0.5) : .clear, radius: 4)
                Text(route.displayName)
                    .aerieFont(AerieFont.body().weight(isSelected ? .semibold : .regular))
                    .tracking(0.3)
                    .foregroundStyle(isSelected ? AerieColor.text1 : AerieColor.text2)
                Spacer(minLength: 8)
                trailingAccessory(route, isSelected: isSelected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(colors: [AerieColor.amberSoft, AerieColor.amber.opacity(0.02)],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(colors: [AerieColor.amberLine, AerieColor.glassLine.opacity(0.4)],
                                                           startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.clear),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    // Glowing gold strut on the leading edge.
                    Rectangle()
                        .fill(AerieColor.amber)
                        .frame(width: 2)
                        .padding(.vertical, 6)
                        .shadow(color: AerieColor.amberGlow, radius: 5)
                }
            }
            // Make the whole row tappable, not just the icon/text glyphs.
            // Plain `Button` style only hits opaque content, so MCP — whose
            // text is shorter than the row — was hard to click anywhere
            // outside the word itself.
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trailingAccessory(_ route: SettingsRoute, isSelected: Bool) -> some View {
        if route == .mcp {
            // Always show an indicator so the row's MCP state is legible:
            // arc cyan + glow while the server is running (live), dim otherwise.
            Circle()
                .fill(mcpRunning ? AerieColor.arc : AerieColor.text4)
                .frame(width: 7, height: 7)
                .shadow(color: mcpRunning ? AerieColor.arcGlow : .clear, radius: 4)
        } else if let n = count(for: route) {
            Text("\(n)")
                .aerieFont(AerieFont.code(11).weight(.medium))
                .tracking(0.6)
                .foregroundStyle(isSelected ? AerieColor.amber : AerieColor.text4)
        }
    }
}
