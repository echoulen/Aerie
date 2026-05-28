import SwiftUI

/// Two-pill segmented control that lives in the titlebar's `mid` slot and
/// toggles between Pull Requests and Repos.
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` lines 100-138.
/// Selected pill: amber-tinted text on `AerieColor.amberSoft` with an
/// `AerieColor.amberLine` 1pt border. Unselected: `AerieColor.text2` text on
/// a transparent background.
///
/// Keyboard shortcuts (⌘1 / ⌘2) live on the segment buttons — see Task 8.2.
struct SegmentedToggle: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 2) {
            segmentButton(tab: .prs, label: "Pull Requests")
            segmentButton(tab: .repos, label: "Repos")
        }
        .padding(3)
        .background(AerieColor.glass2)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segmentButton(tab: MainTab, label: String) -> some View {
        let isSelected = selection == tab
        Button(action: { selection = tab }) {
            Text(label)
                .font(AerieFont.small().weight(.medium))
                .foregroundStyle(isSelected ? AerieColor.amber : AerieColor.text2)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? AerieColor.amberSoft : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? AerieColor.amberLine : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ⌘1 → PRs, ⌘2 → Repos. The shortcut is active whenever this button's
        // host view is in the responder chain (i.e. the main window is key).
        .keyboardShortcut(tab == .prs ? "1" : "2", modifiers: .command)
    }
}
