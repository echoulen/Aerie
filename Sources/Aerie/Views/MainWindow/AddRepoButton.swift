import SwiftUI

/// The small "add repository" button shown in the Repositories page header,
/// after the Refresh button. Mirrors `v2/app.jsx` `AddRepoButton`: a 26×26
/// `.btn.ghost.sm` bevelled key with a gold glyph on a transparent ground and a
/// glass hairline (not the gold-tinted border the Refresh button uses).
///
/// Tapping it opens the existing add-repo flow (Settings · Repositories with
/// the add sheet presented) — see `MainShell`.
struct AddRepoButton: View {
    /// The action to run on tap. Defaults to a no-op so snapshot tests and
    /// previews can render the button without wiring navigation.
    var action: () -> Void = {}

    private static let shape = HudKeyShape(cut: 6)

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(AerieColor.amber)
                .frame(width: 26, height: 26)
                .overlay(Self.shape.strokeBorder(AerieColor.glassLine, lineWidth: 1))
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .help("Add repository")
        .accessibilityLabel("Add repository")
    }
}
