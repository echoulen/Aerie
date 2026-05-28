import SwiftUI
import Combine

@main
struct AerieApp: App {
    @State private var bootstrapper: GhBootstrapper = {
        // Use the live auth service. AerieApp owns the bootstrapper for the
        // process's lifetime.
        let auth = LiveAuthService()
        return GhBootstrapper(auth: auth, interval: 5.0)
    }()

    var body: some Scene {
        WindowGroup("Aerie") {
            AppRoot(bootstrapper: bootstrapper)
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

/// Branches between the first-run flow and the main shell based on the
/// bootstrapper's current ``AuthBootstrapResult``.
private struct AppRoot: View {
    let bootstrapper: GhBootstrapper
    @State private var current: AuthBootstrapResult? = nil
    @State private var sub: AnyCancellable? = nil

    var body: some View {
        Group {
            switch current {
            case .ok:
                ContentView()  // Phase 21 swaps this for the real main shell.
            case .ghMissing, .noAuth, .none:
                FirstRunRoot(bootstrapper: bootstrapper)
            }
        }
        .onAppear {
            sub = bootstrapper.state.sink { current = $0 }
            bootstrapper.start()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Aerie")
            .font(.largeTitle)
    }
}
