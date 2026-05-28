import SwiftUI

@main
struct AerieApp: App {
    var body: some Scene {
        WindowGroup("Aerie") {
            ContentView()
                .frame(minWidth: 1240, minHeight: 880)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }

        Window("Aerie · Settings", id: "settings") {
            SettingsWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

private struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Settings…") {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

struct ContentView: View {
    var body: some View {
        Text("Aerie")
            .font(.largeTitle)
    }
}
