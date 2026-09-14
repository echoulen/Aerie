import SwiftUI

// MARK: - Width classes

/// The main window's adaptive layout tier (`compact.jsx` BreakpointSpec):
///   - `regular` (≥ 1040): full cards, inline actions, page header with tabs.
///   - `medium` (640…1039): one-line rows, tabs move into the titlebar as short
///     codes, row actions collapse to a glyph button + overflow menu.
///   - `compact` (< 640): stacked three-line rows, a tab strip under the
///     titlebar, the review screen's actions in a bottom bar.
enum WidthClass: Int, Comparable {
    case compact, medium, regular

    static func forWidth(_ width: CGFloat) -> WidthClass {
        if width >= AerieMetric.regularWidthBreakpoint { return .regular }
        if width >= AerieMetric.compactWidthBreakpoint { return .medium }
        return .compact
    }

    static func < (lhs: WidthClass, rhs: WidthClass) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// `AppFrame` measures the window once and publishes the tier here, so the
/// titlebar, list screens, cards and review screen all read the same signal
/// instead of each wrapping itself in a `GeometryReader`. Defaults to
/// `.regular` — snapshot tests and previews that don't inject it render the
/// wide layout.
private struct WidthClassKey: EnvironmentKey {
    static let defaultValue = WidthClass.regular
}

/// The measured content width, bucketed to the nearest 8pt. `PageHeader`
/// keys its `ViewThatFits` off this so the choice is force-recomputed on
/// every real width change — on macOS, `ViewThatFits` inside a `ScrollView`
/// can otherwise keep rendering a stale (too-wide) child after a window
/// resize until some unrelated state change forces a fresh layout pass,
/// which reads as clipped/truncated header text at narrow widths.
private struct ContentWidthBucketKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var widthClass: WidthClass {
        get { self[WidthClassKey.self] }
        set { self[WidthClassKey.self] = newValue }
    }
    /// Shorthand for `widthClass == .compact`.
    var isCompactWidth: Bool {
        widthClass == .compact
    }
    var contentWidthBucket: Int {
        get { self[ContentWidthBucketKey.self] }
        set { self[ContentWidthBucketKey.self] = newValue }
    }
}

extension View {
    /// Publishes a measured width tier to this subtree. The measuring view
    /// (`AppFrame`) owns the state so its own chrome can read the tier too.
    func widthClass(_ widthClass: WidthClass, bucket: Int) -> some View {
        environment(\.widthClass, widthClass)
            .environment(\.contentWidthBucket, bucket)
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
            // An item wider than the row is clamped to it (and proposed that
            // width) so truncating content shrinks instead of overflowing.
            let ideal = subview.sizeThatFits(.unspecified)
            var size = ideal
            if ideal.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
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
