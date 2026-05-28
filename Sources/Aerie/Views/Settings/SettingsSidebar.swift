import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsRoute
    /// Whether the MCP server is currently running. Drives the green dot on the MCP row.
    /// Phase 18 will wire this from MCPServer; for Phase 11, callers pass `false`.
    var mcpRunning: Bool = false

    var body: some View {
        VStack(spacing: 4) {
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

    @ViewBuilder
    private func row(_ route: SettingsRoute) -> some View {
        let isSelected = selection == route
        Button(action: { selection = route }) {
            HStack(spacing: 10) {
                Image(systemName: route.systemIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? AerieColor.amber : AerieColor.text2)
                    .frame(width: 18)
                Text(route.displayName)
                    .font(AerieFont.body())
                    .foregroundStyle(isSelected ? AerieColor.text1 : AerieColor.text2)
                Spacer()
                if route == .mcp, mcpRunning {
                    Circle()
                        .fill(AerieColor.ok)
                        .frame(width: 6, height: 6)
                        .shadow(color: AerieColor.ok.opacity(0.6), radius: 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AerieColor.glass3 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? AerieColor.glassLine : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
