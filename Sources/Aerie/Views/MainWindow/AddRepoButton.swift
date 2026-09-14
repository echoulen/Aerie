import SwiftUI

/// The small "add repository" button shown in the Repositories page header,
/// after the Refresh button. Mirrors `v2/app.jsx` `AddRepoButton`: a 26×26
/// gold-glyph ghost bevelled key with a glass hairline (not the gold-tinted
/// border the Refresh button uses) that picks up a gold rim on hover.
///
/// Tapping it opens the existing add-repo flow (Settings · Repositories with
/// the add sheet presented) — see `MainShell`.
struct AddRepoButton: View {
    /// The action to run on tap. Defaults to a no-op so snapshot tests and
    /// previews can render the button without wiring navigation.
    var action: () -> Void = {}

    @State private var hovering = false

    private static let shape = HudKeyShape(cut: 6)

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(AerieColor.amber)
                .frame(width: 26, height: 26)
                .background(Self.shape.fill(hovering ? AerieColor.amberSoft : Color.clear))
                .overlay(
                    Self.shape.strokeBorder(hovering ? AerieColor.amberLine : AerieColor.glassLine, lineWidth: 1)
                )
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Add repository")
        .accessibilityLabel("Add repository")
    }
}
