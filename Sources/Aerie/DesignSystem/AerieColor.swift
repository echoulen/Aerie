import SwiftUI

/// Aerie's color tokens — the v3 "MARK III" HUD palette: hot gold + crimson
/// on deep space. Arc cyan is reserved for live energy (polling ticks,
/// running processes); nothing else gets to glow cyan.
/// (Design source: Claude Design project "Aerie", `src/v2/styles.css`.
///  oklch values converted to sRGB.)
enum AerieColor {
    // Deep-space backdrop
    static let space0 = Color(red: 0x03/255, green: 0x04/255, blue: 0x0a/255)
    static let space1 = Color(red: 0x07/255, green: 0x08/255, blue: 0x18/255)
    static let space2 = Color(red: 0x0d/255, green: 0x0a/255, blue: 0x18/255)
    // Kept for existing call sites.
    static let backdrop1 = space1
    static let backdrop2 = space2

    // Glass — tinted warm so gold hairlines feel emitted, not painted
    private static let warmGlass = Color(red: 1.0, green: 214/255, blue: 160/255)
    private static let warmLine  = Color(red: 1.0, green: 196/255, blue: 120/255)
    static let glass1     = Color(red: 1.0, green: 218/255, blue: 170/255).opacity(0.035)
    static let glass2     = warmGlass.opacity(0.055)
    static let glass3     = warmGlass.opacity(0.105)
    static let glassLine  = warmLine.opacity(0.16)
    static let glassLine2 = warmLine.opacity(0.30)
    static let glassHighlight = Color(red: 1.0, green: 235/255, blue: 205/255).opacity(0.28)

    // Card plate wash — the faint warm gradient at the top of a `.card`.
    static let cardSheen = Color(red: 1.0, green: 206/255, blue: 140/255)
    // Card frosted-glass tint over the behind-window blur (see `GlassModifier`).
    static let cardGlassTint = Color(red: 10/255, green: 9/255, blue: 20/255).opacity(0.72)

    // Dialog / window interior — near-black space glass (`#0b0a16 → #04040a`).
    static let dialogSurface = Color(red: 11/255, green: 10/255, blue: 22/255).opacity(0.90)
    static let hullInteriorTop = Color(red: 11/255, green: 10/255, blue: 22/255)
    static let hullInteriorBot = Color(red: 4/255, green: 4/255, blue: 10/255)
    // Slightly recessed footer band inside a dialog.
    static let dialogFooter  = Color.black.opacity(0.34)
    // Dropdown menu panel — `oklch(0.20 0.012 70 / 0.96)`.
    static let menuSurface = Color(red: 0.10, green: 0.083, blue: 0.063).opacity(0.96)

    // Text — warm white, stepped alpha
    static let text1 = Color(red: 1.0, green: 248/255, blue: 238/255).opacity(0.97)
    static let text2 = Color(red: 1.0, green: 240/255, blue: 224/255).opacity(0.74)
    static let text3 = Color(red: 1.0, green: 232/255, blue: 210/255).opacity(0.52)
    static let text4 = Color(red: 1.0, green: 226/255, blue: 200/255).opacity(0.46)

    // Primary accent — hot gold `oklch(0.86 0.155 85)` (kept under `amber`)
    static let amber     = Color(red: 1.0, green: 0.784, blue: 0.264)
    static let amber2    = Color(red: 0.909, green: 0.589, blue: 0.161)  // oklch(0.74 0.150 68)
    static let amberSoft = amber.opacity(0.13)
    static let amberLine = amber.opacity(0.42)
    static let amberGlow = amber.opacity(0.70)

    // Gold primary CTA (`.btn.amber`) — vertical gradient, dark ink, bright rim.
    static let amberFillTop = Color(red: 1.0, green: 0.873, blue: 0.406)  // oklch(0.92 0.145 88)
    static let amberFillBot = Color(red: 0.955, green: 0.646, blue: 0.17) // oklch(0.78 0.155 72)
    static let amberInk     = Color(red: 0.121, green: 0.063, blue: 0.01) // oklch(0.19 0.04 70)
    static let amberCtaLine = Color(red: 1.0, green: 0.917, blue: 0.614)  // oklch(0.94 0.10 92)

    // Crimson — danger / destructive
    static let crimson     = Color(red: 0.982, green: 0.284, blue: 0.273) // oklch(0.66 0.215 26)
    static let crimsonHot  = Color(red: 1.0, green: 0.465, blue: 0.405)   // oklch(0.76 0.195 28)
    static let crimsonSoft = crimson.opacity(0.14)
    static let crimsonLine = crimson.opacity(0.45)

    // Arc reactor cyan — energy only: live polling, running processes
    static let arc     = Color(red: 0.263, green: 0.931, blue: 0.997)     // oklch(0.87 0.135 205)
    static let arcSoft = arc.opacity(0.13)
    static let arcLine = arc.opacity(0.42)
    static let arcGlow = arc.opacity(0.65)

    // Status
    static let ok   = Color(red: 0.491, green: 0.929, blue: 0.625)  // oklch(0.86 0.150 152)
    static let warn = Color(red: 0.971, green: 0.818, blue: 0.309)  // oklch(0.87 0.150 92)
    static let err  = crimsonHot

    // Danger button (`.btn.danger`) — crimson-hot text on a crimson wash.
    static let dangerText      = crimsonHot
    static let dangerLine      = crimsonLine
    static let dangerFill      = crimsonSoft
    static let dangerFillHover = crimson.opacity(0.26)

    // Window hull edge gradient (`.window` background, 150deg)
    static let hullEdgeA = Color(red: 1.0, green: 0.853, blue: 0.402)     // oklch(0.90 0.14 90)
    static let hullEdgeB = Color(red: 0.883, green: 0.564, blue: 0.12)    // oklch(0.72 0.15 68)

    // Diff viewer
    static let diffAddBg   = ok.opacity(0.10)
    static let diffAddText = Color(red: 0.733, green: 0.98, blue: 0.794)  // oklch(0.93 0.09 152)
    static let diffDelBg   = crimson.opacity(0.13)
    static let diffDelText = Color(red: 1.0, green: 0.697, blue: 0.658)   // oklch(0.86 0.12 26)
    static let diffHunkBg  = amber.opacity(0.07)
    static let tokKeyword  = Color(red: 0.799, green: 0.659, blue: 1.0)   // oklch(0.80 0.14 300)
    static let tokString   = Color(red: 0.548, green: 0.916, blue: 0.653) // oklch(0.86 0.13 152)
}
