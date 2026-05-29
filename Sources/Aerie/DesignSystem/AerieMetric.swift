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
    /// Custom titlebar height. Matches the native macOS title-bar band (32 pt on
    /// macOS 26) so that the centred brand cluster lands at 16 pt — the measured
    /// vertical centre of the traffic-light buttons — keeping "Aerie" + the
    /// account avatar level with the system window controls.
    static let titlebarHeight: CGFloat = 32
    static let mainWindowW: CGFloat = 1240
    static let mainWindowH: CGFloat = 880
    static let settingsWindowW: CGFloat = 1040
    static let settingsWindowH: CGFloat = 760
}
