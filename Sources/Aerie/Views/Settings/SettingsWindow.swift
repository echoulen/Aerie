import SwiftUI

struct SettingsWindow: View {
    @SceneStorage("settings.route") private var routeRaw: String = SettingsRoute.accounts.rawValue
    private var route: Binding<SettingsRoute> {
        Binding(
            get: { SettingsRoute(rawValue: routeRaw) ?? .accounts },
            set: { routeRaw = $0.rawValue }
        )
    }

    /// Phase 11.2 will replace this with a real sidebar; for now, a placeholder.
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                Titlebar(
                    mid: { Text("Aerie · Settings")
                            .font(AerieFont.body().weight(.medium))
                            .foregroundStyle(AerieColor.text1) },
                    trail: { EmptyView() }
                )
                HStack(spacing: 0) {
                    // Sidebar slot — filled in Task 11.2
                    Rectangle()
                        .fill(AerieColor.glass1)
                        .frame(width: 220)
                        .overlay(
                            Rectangle()
                                .fill(AerieColor.glassLine)
                                .frame(width: 1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        )
                    // Body slot — filled by route-specific screens in later phases
                    ZStack {
                        Color.clear
                        Text(route.wrappedValue.displayName)
                            .font(AerieFont.sectionTitle())
                            .foregroundStyle(AerieColor.text2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: AerieMetric.settingsWindowW, minHeight: AerieMetric.settingsWindowH)
    }
}
