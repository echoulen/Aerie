import SwiftUI

/// First-run body shown when `gh` is installed but no accounts are
/// authenticated. Adds a `.card` tip block under the command box.
struct NoAuthBody: View {
    var onRecheck: () -> Void
    var body: some View {
        FirstRunPanel(
            icon: "person.badge.key",
            title: "Log in to GitHub",
            prose: "Run gh auth login below, then Aerie will pick up the credentials within 5 seconds.",
            command: "gh auth login --hostname github.com --git-protocol ssh",
            primaryButtonTitle: "I've logged in — re-check",
            onPrimary: onRecheck,
            actionsSpacing: 28
        ) {
            Text("On GitHub Enterprise? Swap --hostname github.com for your GHE host.")
                .aerieFont(AerieFont.custom(.sans, size: 12))
                .foregroundStyle(AerieColor.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(.card)
                .padding(.top, 18)
        }
    }
}
