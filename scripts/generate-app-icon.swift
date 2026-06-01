#!/usr/bin/env swift
//
// Generates the Aerie app icon PNG set for the macOS asset catalog.
//
// Faithfully reproduces docs/superpowers/design/v2/icon.jsx (`AppIcon`):
//   • Dark glass squircle (border-radius ≈ 22.5% of size)
//   • Diagonal warm→cool linear gradient
//   • Warm radial wash at top-left + cool radial wash at bottom-right
//   • Top/bottom inset highlight + lowlight
//   • SVG-style radar layer (viewBox 100×100, center at 50,55):
//       - 4 concentric range rings (r = 14/22/30/38) amber, faint
//       - faint cross hairs
//       - amber sweep wedge from top to right
//       - soft amber halo around the orb
//       - sodium-amber orb (r = 12) with off-center radial gradient
//       - white specular highlight ellipse on the orb
//   • Top-edge white highlight gradient (top 30%)
//   • "AERIE" wordmark at bottom (only when image is ≥ 96 px)
//
// The viewBox coordinates from icon.jsx are SVG (y grows downward); this
// script maps them into CG (y grows upward) via the `y()` / `flipY()`
// helpers. Distances are scaled linearly via `s`.

import AppKit
import CoreGraphics

struct IconSpec {
    let size: Int
    let scale: Int
    var dimension: Int { size * scale }
    var filename: String {
        scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    }
}

let specs: [IconSpec] = [
    .init(size: 16,  scale: 1), .init(size: 16,  scale: 2),
    .init(size: 32,  scale: 1), .init(size: 32,  scale: 2),
    .init(size: 128, scale: 1), .init(size: 128, scale: 2),
    .init(size: 256, scale: 1), .init(size: 256, scale: 2),
    .init(size: 512, scale: 1), .init(size: 512, scale: 2),
]

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                 ?? "Sources/Aerie/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// Approximated sRGB equivalents of the oklch colors used in icon.jsx.
enum Palette {
    // Background gradients
    static let warmDim    = rgb(0.29, 0.24, 0.20)              // oklch(0.30 0.04 70)
    static let coolDim    = rgb(0.13, 0.13, 0.22, 0.6)         // oklch(0.18 0.06 290 / 0.6)
    static let linearTop  = rgb(0.21, 0.18, 0.17)              // oklch(0.22 0.02 70)
    static let linearBot  = rgb(0.07, 0.08, 0.10)              // oklch(0.10 0.01 270)
    // Radar amber family
    static let amberLight = rgb(0.99, 0.81, 0.49)              // oklch(0.85 0.15 75)
    static let amberPale  = rgb(1.00, 0.91, 0.62)              // oklch(0.95 0.16 80)
    static let amberMid   = rgb(0.67, 0.45, 0.20)              // oklch(0.55 0.14 60)
    static let amberDeep  = rgb(0.70, 0.42, 0.13)              // oklch(0.55 0.16 60)
    static let amberDark  = rgb(0.41, 0.29, 0.16, 0.0)         // oklch(0.35 0.08 50, 0)
    // Orb
    static let orbBright  = rgb(1.00, 0.96, 0.75)              // oklch(0.98 0.10 80)
    static let orbMid     = rgb(0.99, 0.81, 0.49)              // oklch(0.85 0.15 75)
    static let orbDeep    = rgb(0.70, 0.42, 0.13)              // oklch(0.55 0.16 60)
    // Wordmark
    static let wordmark   = NSColor(red: 0.96, green: 0.88, blue: 0.74, alpha: 0.85)
    static let wordShadow = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.60)
}

func renderIcon(dim: Int) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: dim, height: dim,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let D = CGFloat(dim)
    let s = D / 100.0   // viewBox unit → pixels
    // SVG → CG y-flip helpers. SVG y=0 is top; CG y=0 is bottom.
    func y(_ svgY: CGFloat) -> CGFloat { (100 - svgY) * s }
    func x(_ svgX: CGFloat) -> CGFloat { svgX * s }
    func d(_ svgD: CGFloat) -> CGFloat { svgD * s }

    ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))

    // ---------- Squircle clip ----------
    let cornerR = D * 0.225
    let squircle = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: D, height: D),
        cornerWidth: cornerR, cornerHeight: cornerR,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // ---------- Dark glass base ----------
    // Linear 155deg from oklch(0.22 0.02 70) → oklch(0.10 0.01 270).
    // 155deg in CSS = pointing down + slightly left. Closest CG direction:
    // start at top-right, end at bottom-left.
    let baseGradient = CGGradient(colorsSpace: cs, colors: [
        Palette.linearTop,
        Palette.linearBot,
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        baseGradient,
        start: CGPoint(x: D * 0.78, y: D),          // top-right-ish in CG
        end:   CGPoint(x: D * 0.22, y: 0),          // bottom-left-ish in CG
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Warm radial wash from top-left of the squircle (SVG (20%, 0%)).
    let warmWash = CGGradient(colorsSpace: cs, colors: [
        Palette.warmDim,
        Palette.warmDim.copy(alpha: 0)!,
    ] as CFArray, locations: [0.0, 0.55])!
    ctx.drawRadialGradient(
        warmWash,
        startCenter: CGPoint(x: x(20), y: y(0)),
        startRadius: 0,
        endCenter: CGPoint(x: x(20), y: y(0)),
        endRadius: D * 0.72,
        options: []
    )

    // Cool radial wash from bottom-right (SVG (80%, 100%)).
    let coolWash = CGGradient(colorsSpace: cs, colors: [
        Palette.coolDim,
        Palette.coolDim.copy(alpha: 0)!,
    ] as CFArray, locations: [0.0, 0.6])!
    ctx.drawRadialGradient(
        coolWash,
        startCenter: CGPoint(x: x(80), y: y(100)),
        startRadius: 0,
        endCenter: CGPoint(x: x(80), y: y(100)),
        endRadius: D * 0.60,
        options: []
    )

    // ---------- Radar layer ----------
    let cx = x(50)
    let cy = y(55)

    // Concentric range rings at r = 14, 22, 30, 38; amber stroke alpha 0.18.
    let ringStroke = Palette.amberLight.copy(alpha: 0.18)!
    ctx.setStrokeColor(ringStroke)
    ctx.setLineWidth(max(0.5, 0.4 * s))
    for r in [14.0, 22.0, 30.0, 38.0] {
        let R = d(CGFloat(r))
        ctx.strokeEllipse(in: CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2))
    }

    // Cross hairs (faint amber).
    let hairStroke = Palette.amberLight.copy(alpha: 0.10)!
    ctx.setStrokeColor(hairStroke)
    ctx.setLineWidth(max(0.4, 0.3 * s))
    ctx.beginPath()
    // Vertical: x=50, y from 13 to 97 (SVG).
    ctx.move(to: CGPoint(x: x(50), y: y(13)))
    ctx.addLine(to: CGPoint(x: x(50), y: y(97)))
    // Horizontal: y=55, x from 8 to 92.
    ctx.move(to: CGPoint(x: x(8),  y: y(55)))
    ctx.addLine(to: CGPoint(x: x(92), y: y(55)))
    ctx.strokePath()

    // Radar sweep wedge: M 50,55 L 50,17 → arc to 88,55 → close.
    // In CG (y-up), top is angle π/2, right is angle 0; clockwise=true
    // walks from top to right in the displayed image.
    ctx.saveGState()
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: x(50), y: y(17)))
    ctx.addArc(
        center: CGPoint(x: cx, y: cy),
        radius: d(38),
        startAngle: .pi / 2,
        endAngle: 0,
        clockwise: true
    )
    ctx.closePath()
    ctx.clip()
    let sweepGradient = CGGradient(colorsSpace: cs, colors: [
        Palette.amberLight.copy(alpha: 0.0)!,
        Palette.amberLight.copy(alpha: 0.55)!,
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        sweepGradient,
        start: CGPoint(x: 0, y: cy),
        end:   CGPoint(x: D, y: cy),
        options: []
    )
    ctx.restoreGState()

    // Outer amber halo (radial), opacity 0.28 — anchored at the orb center,
    // extending out to ~32 SVG units.
    let haloGradient = CGGradient(colorsSpace: cs, colors: [
        Palette.amberPale.copy(alpha: 0.28)!,
        Palette.amberLight.copy(alpha: 0.25)!,
        Palette.amberMid.copy(alpha: 0.12)!,
        Palette.amberDark,
    ] as CFArray, locations: [0.0, 0.35, 0.70, 1.0])!
    ctx.drawRadialGradient(
        haloGradient,
        startCenter: CGPoint(x: cx, y: cy),
        startRadius: 0,
        endCenter:   CGPoint(x: cx, y: cy),
        endRadius:   d(32),
        options: []
    )

    // ---------- Orb (r = 12 SVG units) ----------
    let orbR = d(12)
    let orbRect = CGRect(x: cx - orbR, y: cy - orbR, width: orbR * 2, height: orbR * 2)
    // Orb gradient center: SVG (40%, 35%) of orb bounds, then y-flipped to CG.
    let orbHotspot = CGPoint(
        x: orbRect.minX + 0.40 * (orbR * 2),
        y: orbRect.maxY - 0.35 * (orbR * 2)   // flip
    )
    let orbGradient = CGGradient(colorsSpace: cs, colors: [
        Palette.orbBright,
        Palette.orbMid,
        Palette.orbDeep,
    ] as CFArray, locations: [0.0, 0.5, 1.0])!
    ctx.saveGState()
    ctx.addEllipse(in: orbRect)
    ctx.clip()
    ctx.drawRadialGradient(
        orbGradient,
        startCenter: orbHotspot,
        startRadius: 0,
        endCenter:   CGPoint(x: cx, y: cy),
        endRadius:   orbR,
        options: []
    )
    ctx.restoreGState()

    // Specular highlight on the orb: white ellipse rx=4.5 ry=2.6 at SVG (46, 50).
    let hx = x(46), hy = y(50)
    let hrx = d(4.5), hry = d(2.6)
    ctx.setFillColor(rgb(1, 1, 1, 0.55))
    ctx.fillEllipse(in: CGRect(x: hx - hrx, y: hy - hry, width: hrx * 2, height: hry * 2))

    // ---------- Top-edge highlight gradient (top 30% of squircle) ----------
    let topHi = CGGradient(colorsSpace: cs, colors: [
        rgb(1, 1, 1, 0.06),
        rgb(1, 1, 1, 0.0),
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        topHi,
        start: CGPoint(x: 0, y: D),
        end:   CGPoint(x: 0, y: D * 0.70),
        options: []
    )

    // ---------- Inset highlight / lowlight (1px lines) ----------
    ctx.setFillColor(rgb(1, 1, 1, 0.10))
    ctx.fill(CGRect(x: 0, y: D - max(1, s * 0.5), width: D, height: max(1, s * 0.5)))
    ctx.setFillColor(rgb(0, 0, 0, 0.40))
    ctx.fill(CGRect(x: 0, y: 0, width: D, height: max(1, s * 0.5)))

    ctx.restoreGState()   // pop squircle clip

    // ---------- "AERIE" wordmark (only when image is large enough) ----------
    if dim >= 96 {
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        let fontSize = D * 0.075
        let kern = fontSize * 0.18                          // CSS letter-spacing 0.18em
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let text = "AERIE"

        func attrs(color: NSColor) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: color, .kern: kern]
        }

        let str    = NSAttributedString(string: text, attributes: attrs(color: Palette.wordmark))
        let shadow = NSAttributedString(string: text, attributes: attrs(color: Palette.wordShadow))
        let size   = str.size()
        // CSS positions the wordmark at `bottom: r * 0.10` from the bottom edge.
        // The `.size()` height is the typographic line, so we offset by descender
        // to make the baseline sit ~10% from the bottom.
        let xPos = (D - size.width) / 2
        let yPos = D * 0.10                                 // CG y from bottom

        shadow.draw(at: NSPoint(x: xPos, y: yPos - max(1, s * 0.5)))
        str.draw(at: NSPoint(x: xPos, y: yPos))

        NSGraphicsContext.restoreGraphicsState()
    }

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])!
}

for spec in specs {
    let data = renderIcon(dim: spec.dimension)
    let url = outDir.appendingPathComponent(spec.filename)
    try data.write(to: url)
    print("Wrote \(spec.filename) (\(spec.dimension)×\(spec.dimension))")
}
