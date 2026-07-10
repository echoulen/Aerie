import SwiftUI

// MARK: - Compact-width environment

/// Whether the window is narrower than ``AerieMetric/compactWidthBreakpoint``.
/// `MainShell` measures the tab content area once and publishes the flag here,
/// so every list screen / card reads the same signal instead of each view
/// wrapping itself in a `GeometryReader`. Defaults to `false` — snapshot tests
/// and previews that don't inject it render the wide layout.
private struct IsCompactWidthKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isCompactWidth: Bool {
        get { self[IsCompactWidthKey.self] }
        set { self[IsCompactWidthKey.self] = newValue }
    }
}

extension View {
    /// Measures this view's width and publishes `\.isCompactWidth` to its
    /// subtree. Apply once at the shell level, above the list screens.
    func readsCompactWidth() -> some View {
        modifier(CompactWidthReader())
    }
}

private struct CompactWidthReader: ViewModifier {
    @State private var isCompact = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.width < AerieMetric.compactWidthBreakpoint
            } action: { compact in
                isCompact = compact
            }
            .environment(\.isCompactWidth, isCompact)
    }
}

// MARK: - Flow layout

/// A leading-aligned wrapping row — like an `HStack` that breaks onto a new
/// line when it runs out of width. Used for card chip rows and compact action
/// rows, where the fixed-size pills previously forced the card wider than the
/// window instead of wrapping.
///
/// Items keep their ideal size; rows are `rowSpacing` apart and each item is
/// vertically centred within its row.
struct FlowLayout: Layout {
    var itemSpacing: CGFloat = 10
    var rowSpacing: CGFloat = 8

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let widthIfAppended = current.items.isEmpty
                ? size.width
                : current.width + itemSpacing + size.width
            if !current.items.isEmpty && widthIfAppended > maxWidth {
                rows.append(current)
                current = Row(items: [(index, size)], width: size.width, height: size.height)
            } else {
                current.items.append((index, size))
                current.width = widthIfAppended
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height }
            + rowSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + itemSpacing
            }
            y += row.height + rowSpacing
        }
    }
}
