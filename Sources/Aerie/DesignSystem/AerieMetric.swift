import SwiftUI

enum AerieMetric {
    // Radii
    static let radiusCard:  CGFloat = 14
    static let radiusRow:   CGFloat = 12
    static let radiusPill:  CGFloat = 999
    static let radiusWindow: CGFloat = 16
    static let radiusDialog: CGFloat = 18

    // Spacing
    static let pagePadding: CGFloat = 44
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
    static let mainWindowW: CGFloat = 1240
    static let mainWindowH: CGFloat = 880
    static let settingsWindowW: CGFloat = 1040
    static let settingsWindowH: CGFloat = 760
}
