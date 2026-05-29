import SwiftUI

/// Aerie's color tokens. Values match the design's CSS variables.
/// (Design source: docs/superpowers/design/v2/styles.css)
enum AerieColor {
    // Backdrop
    static let backdrop1 = Color(red: 0x0b/255, green: 0x0b/255, blue: 0x10/255)
    static let backdrop2 = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)

    // Glass surfaces (white with alpha)
    static let glass1     = Color.white.opacity(0.035)
    static let glass2     = Color.white.opacity(0.055)
    static let glass3     = Color.white.opacity(0.085)
    static let glassLine  = Color.white.opacity(0.08)
    static let glassLine2 = Color.white.opacity(0.14)
    static let glassHighlight = Color.white.opacity(0.22)

    // Dialog surface — dark warm-tinted, sits over a within-window blur.
    // Matches design `rgba(28, 26, 32, 0.78)`: opaque enough to read dark,
    // not the milky white-on-glass that .glass2 produced on the dialog.
    static let dialogSurface = Color(red: 28/255, green: 26/255, blue: 32/255).opacity(0.78)
    // Slightly recessed footer band inside a dialog (`rgba(0,0,0,0.18)`).
    static let dialogFooter  = Color.black.opacity(0.18)

    // Text (white + stepped alpha)
    static let text1 = Color.white.opacity(0.96)
    static let text2 = Color.white.opacity(0.72)
    static let text3 = Color.white.opacity(0.50)
    static let text4 = Color.white.opacity(0.32)

    // Sodium amber accent — oklch(0.86 0.140 78)
    static let amber     = Color(red: 0.98, green: 0.75, blue: 0.30)
    static let amberSoft = amber.opacity(0.14)
    static let amberLine = amber.opacity(0.32)
    static let amberGlow = amber.opacity(0.55)

    // Status — desaturated
    static let ok   = Color(red: 0.52, green: 0.85, blue: 0.65)  // oklch(0.82 0.130 158)
    static let warn = Color(red: 0.94, green: 0.78, blue: 0.30)  // oklch(0.86 0.140 88)
    static let err  = Color(red: 0.96, green: 0.42, blue: 0.40)  // oklch(0.74 0.165 26)
}
