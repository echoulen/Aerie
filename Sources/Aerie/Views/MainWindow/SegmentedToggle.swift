import SwiftUI

/// Three-pill segmented control that lives in the page header's trailing slot
/// and toggles between Pull Requests, Issues, and Repositories.
///
/// Visual contract: `v2/app.jsx` `Header` segmented switch (three buttons).
/// Selected pill: amber-tinted text on `AerieColor.amberSoft` with an
/// `AerieColor.amberLine` 1pt border. Unselected: `AerieColor.text2` text on
/// a transparent background.
///
/// Keyboard shortcuts (⌘1 / ⌘2 / ⌘3) live on the segment buttons.
struct SegmentedToggle: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 2) {
            segmentButton(tab: .prs, label: "Pull Requests")
            segmentButton(tab: .issues, label: "Issues")
            segmentButton(tab: .repos, label: "Repositories")
        }
        .padding(3)
        .background(AerieColor.glass2)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }

    /// ⌘1 → PRs, ⌘2 → Issues, ⌘3 → Repos.
    private func shortcut(for tab: MainTab) -> KeyEquivalent {
        switch tab {
        case .prs:    return "1"
        case .issues: return "2"
        case .repos:  return "3"
        }
    }

    @ViewBuilder
    private func segmentButton(tab: MainTab, label: String) -> some View {
        let isSelected = selection == tab
        Button(action: { selection = tab }) {
            Text(label)
                .aerieFont(AerieFont.small().weight(.medium))
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
        // The shortcut is active whenever this button's host view is in the
        // responder chain (i.e. the main window is key).
        .keyboardShortcut(shortcut(for: tab), modifiers: .command)
    }
}
