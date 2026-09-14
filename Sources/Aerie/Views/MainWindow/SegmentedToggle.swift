import SwiftUI

/// Three-pill segmented control that lives in the page header's trailing slot
/// and toggles between Pull Requests, Issues, and Repositories.
///
/// Visual contract: `v2/app.jsx` `Header` segmented switch (three buttons).
/// MARK III `.segmented`: uppercase 600 labels in a recessed black well; the
/// selected key glows gold with an `amberLine` border. Unselected: `text3`.
///
/// Keyboard shortcuts (⌘1 / ⌘2 / ⌘3) live on the segment buttons.
struct SegmentedToggle: View {
    @Binding var selection: MainTab
    /// When set, the medium-width variant (`compact.jsx` `MediumPRList`): each
    /// segment shows its two-letter code plus the tab's count ("PR 13").
    var counts: [MainTab: Int]? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                segmentButton(tab: tab)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.40))
        .clipShape(RoundedRectangle(cornerRadius: AerieMetric.radiusPill))
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }


    @ViewBuilder
    private func segmentButton(tab: MainTab) -> some View {
        let isSelected = selection == tab
        Button(action: { selection = tab }) {
            HStack(spacing: 6) {
                Text((counts == nil ? tab.title : tab.shortCode).uppercased())
                    .aerieFont(AerieFont.small().weight(.semibold))
                    .tracking(0.96)                      // 0.08em @ 12pt
                if let counts {
                    // Mono count after the code (`MediumPRList` titlebar).
                    Text("\(counts[tab] ?? 0)")
                        .aerieFont(AerieFont.code(10))
                        .opacity(isSelected ? 0.85 : 0.7)
                }
            }
                .lineLimit(1)
                .foregroundStyle(isSelected ? AerieColor.amber : AerieColor.text3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: AerieMetric.radiusPill)
                        .fill(isSelected
                              ? AnyShapeStyle(LinearGradient(colors: [AerieColor.glass3, AerieColor.cardSheen.opacity(0.04)],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AerieMetric.radiusPill)
                        .strokeBorder(isSelected ? AerieColor.amberLine : Color.clear, lineWidth: 1)
                )
                .shadow(color: isSelected ? AerieColor.amberGlow.opacity(0.35) : .clear, radius: 8)
                .animation(.easeOut(duration: 0.2), value: isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The shortcut is active whenever this button's host view is in the
        // responder chain (i.e. the main window is key).
        .keyboardShortcut(tab.shortcut, modifiers: .command)
    }
}
