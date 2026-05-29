import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsRoute
    /// Whether the MCP server is currently running. Drives the colour of the
    /// MCP row's status dot (green = running, dim = stopped).
    var mcpRunning: Bool = false
    /// Live counts shown on the right of the Accounts / Repositories rows,
    /// matching the design. `nil` hides the count (e.g. in isolation tests).
    var accountsCount: Int? = nil
    var repositoriesCount: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SETTINGS")
                .font(AerieFont.eyebrow())
                .tracking(2.0)
                .foregroundStyle(AerieColor.text4)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 10)

            ForEach(routesAbove, id: \.self) { route in
                row(route)
            }
            Spacer()
            row(.about)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(width: 220)
        .background(
            Rectangle()
                .fill(AerieColor.glass1)
                .overlay(
                    Rectangle()
                        .fill(AerieColor.glassLine)
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
        case .mcp:          return .plug
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
                    .font(AerieFont.body())
                    .foregroundStyle(isSelected ? AerieColor.text1 : AerieColor.text2)
                Spacer(minLength: 8)
                trailingAccessory(route)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AerieColor.glass3 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? AerieColor.glassLine : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trailingAccessory(_ route: SettingsRoute) -> some View {
        if route == .mcp {
            // Always show an indicator so the row's MCP state is legible:
            // green + glow when the server is running, dim otherwise.
            Circle()
                .fill(mcpRunning ? AerieColor.ok : AerieColor.text4)
                .frame(width: 7, height: 7)
                .shadow(color: mcpRunning ? AerieColor.ok.opacity(0.6) : .clear, radius: 3)
        } else if let n = count(for: route) {
            Text("\(n)")
                .font(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
        }
    }
}
