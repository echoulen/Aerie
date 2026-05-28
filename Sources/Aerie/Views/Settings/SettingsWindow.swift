import SwiftUI

struct SettingsWindow: View {
    @SceneStorage("settings.route") private var routeRaw: String = SettingsRoute.accounts.rawValue
    private var route: Binding<SettingsRoute> {
        Binding(
            get: { SettingsRoute(rawValue: routeRaw) ?? .accounts },
            set: { routeRaw = $0.rawValue }
        )
    }

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
                    SettingsSidebar(selection: route, mcpRunning: false)
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
