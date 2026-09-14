import SwiftUI

enum AerieMetric {
    // Radii — MARK III is angular: plates are chamfered (see `HudPlateShape`)
    // and the few remaining rounded rects are nearly square.
    static let radiusCard:  CGFloat = 3
    static let radiusRow:   CGFloat = 3
    /// Pills, chips and small controls (`.pill`, `.segmented`, `.wt-*`): 2px.
    static let radiusPill:  CGFloat = 2
    static let radiusWindow: CGFloat = 3
    static let radiusDialog: CGFloat = 3

    // Chamfer cuts
    static let cutCard:   CGFloat = 16
    static let cutDialog: CGFloat = 18
    static let cutWindow: CGFloat = 26
    /// Trailing space titlebar controls keep so they clear the hull's
    /// top-right notched step (`HullShape.notchInset` + a little air).
    static let hullNotchClearance: CGFloat = 140

    // Spacing
    static let pagePadding: CGFloat = 44
    /// Page gutter when the window is narrower than
    /// ``compactWidthBreakpoint`` — the 44pt gutters eat too much of a narrow
    /// window, so the list screens drop to this.
    static let pagePaddingCompact: CGFloat = 24
    static let cardPaddingV: CGFloat = 22
    static let cardPaddingH: CGFloat = 26
    static let cardGap:     CGFloat = 14

    // Window dimensions
    /// Custom titlebar height. Taller than the native title-bar band to give the
    /// centred brand cluster breathing room above and below, matching the v2
    /// design. The brand (and the account avatar) centre vertically here at
    /// 26 pt; the native traffic lights are pinned by the system at 16 pt, so by
    /// design the brand sits a touch below them in exchange for the padding.
    static let titlebarHeight: CGFloat = 52
    static let mainWindowW: CGFloat = 420
    static let mainWindowH: CGFloat = 880
    /// Below this content width the main-window lists switch to the compact
    /// layout (actions under the card content, tighter gutters). See
    /// `\.isCompactWidth` in AdaptiveLayout.swift.
    static let compactWidthBreakpoint: CGFloat = 640
    static let settingsWindowW: CGFloat = 1040
    static let settingsWindowH: CGFloat = 760
}
