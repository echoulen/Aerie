import SwiftUI

@main
struct AerieApp: App {
    var body: some Scene {
        WindowGroup("Aerie") {
            ContentView()
                .frame(minWidth: 1240, minHeight: 880)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    var body: some View {
        Text("Aerie")
            .font(.largeTitle)
    }
}
