import SwiftUI

extension MainTab {
    /// Full label used by the regular-width page header's segmented switch.
    var title: String {
        switch self {
        case .prs:    return "Pull Requests"
        case .issues: return "Issues"
        case .repos:  return "Repositories"
        }
    }

    /// Two-letter code used once the window is too narrow for full labels
    /// (`compact.jsx`: "PR", "IS", "RE").
    var shortCode: String {
        switch self {
        case .prs:    return "PR"
        case .issues: return "IS"
        case .repos:  return "RE"
        }
    }

    /// ⌘1 → PRs, ⌘2 → Issues, ⌘3 → Repos.
    var shortcut: KeyEquivalent {
        switch self {
        case .prs:    return "1"
        case .issues: return "2"
        case .repos:  return "3"
        }
    }
}

/// What the window chrome needs to render the tab switcher itself at medium and
/// compact widths, where the page header (and its switch) is gone.
struct MainTabBar {
    var selection: Binding<MainTab>
    var counts: [MainTab: Int]
}

/// `compact.jsx` `CompactTabs` — the compact tier's equal-width tab strip under
/// the titlebar: bevelled cut-7 keys with a two-letter code and the tab's count;
/// the active key is gold on a gold wash, the rest text-3 on black/0.28.
struct CompactTabStrip: View {
    let bar: MainTabBar

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                key(tab)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func key(_ tab: MainTab) -> some View {
        let on = bar.selection.wrappedValue == tab
        let shape = HudKeyShape(cut: 7)
        return Button {
            bar.selection.wrappedValue = tab
        } label: {
            HStack(spacing: 7) {
                Text(tab.shortCode)
                    .aerieFont(AerieFont.custom(.sans, size: 11).weight(.semibold))
                    .tracking(1.54)                      // 0.14em @ 11pt
                Text("\(bar.counts[tab] ?? 0)")
                    .aerieFont(AerieFont.code(10))
                    .opacity(0.8)
            }
            .foregroundStyle(on ? AerieColor.amber : AerieColor.text3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(shape.fill(on ? AerieColor.amberSoft : Color.black.opacity(0.28)))
            .overlay(shape.strokeBorder(on ? AerieColor.amberLine : AerieColor.glassLine, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tab.shortcut, modifiers: .command)
        .help(tab.title)
        .animation(.easeOut(duration: 0.2), value: on)
    }
}

// MARK: - List chrome for medium / compact

/// Per-tier spacing for the three tab lists (`compact.jsx`): regular keeps the
/// 44pt gutters under a full page header; medium tightens to 22pt / 9pt row
/// gaps; compact to 18pt.
struct ListLayout {
    let widthClass: WidthClass

    var gutter: CGFloat {
        switch widthClass {
        case .regular: return AerieMetric.pagePadding
        case .medium:  return 22
        case .compact: return 18
        }
    }
    var top: CGFloat {
        switch widthClass {
        case .regular: return 12
        case .medium:  return 12
        case .compact: return 0
        }
    }
    var bottom: CGFloat {
        switch widthClass {
        case .regular: return 12
        case .medium:  return 20
        case .compact: return 18
        }
    }
    /// Space between the header / subheader and the first row.
    var headerGap: CGFloat {
        switch widthClass {
        case .regular: return 18
        case .medium:  return 14
        case .compact: return 10
        }
    }
    /// Space between rows. Regular falls back to each list's own card gap.
    func rowGap(regular: CGFloat) -> CGFloat { widthClass == .regular ? regular : 9 }
}

/// Replaces `PageHeader` below regular width (`compact.jsx` `CompactPRList`):
/// a gold-ticked telemetry note summarising the list ("13 open · 4 yours"),
/// with the refresh key — and any extra action — on the right. The tab switch
/// itself has moved into the window chrome.
struct ListSubheader<Trailing: View>: View {
    let summary: String
    var onRefresh: () async -> Void = {}
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            HudNote(text: summary, truncates: true)
            Spacer(minLength: 8)
            RefreshButton(action: onRefresh)
            trailing()
        }
    }
}

extension ListSubheader where Trailing == EmptyView {
    init(summary: String, onRefresh: @escaping () async -> Void = {}) {
        self.init(summary: summary, onRefresh: onRefresh, trailing: { EmptyView() })
    }
}
