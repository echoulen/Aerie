import SwiftUI

/// First-run body shown when `gh` is installed but no accounts are
/// authenticated.
struct NoAuthBody: View {
    var onRecheck: () -> Void
    var body: some View {
        FirstRunPanel(
            title: "Log in to GitHub",
            prose: "Run gh auth login below, then Aerie will pick up the credentials within 5 seconds.",
            command: "gh auth login --hostname github.com --git-protocol ssh",
            primaryButtonTitle: "I've logged in — re-check",
            onPrimary: onRecheck
        ) {
            Text("On GitHub Enterprise? Swap --hostname github.com for your GHE host.")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
    }
}
