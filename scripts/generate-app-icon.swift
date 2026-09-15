#!/usr/bin/env swift
//
// Generates the Aerie app icon: the asset-catalog PNG set plus the About
// screen's `app-icon.png`.
//
//     swift scripts/generate-app-icon.swift [appiconset-dir] [about-png]
//
// Reproduces the design's MARK III arc reactor (claude.ai/design project
// "Aerie", `src/v2/icon.jsx` → `AppIcon`): a dark-alloy squircle holding a
// segmented energy ring, six radial struts, a triangular reactor core, and an
// etched HUD reticle with tick rails.
//
// Fidelity notes — each mirrors how a browser renders the design:
//   • Colours are the design's oklch values converted exactly (OKLab → linear
//     sRGB → sRGB, per-channel clip), not eyeballed approximations.
//   • The CSS background gradients use oklch colours, so CSS interpolates
//     them in OKLab; they're expanded into dense sRGB stops here. SVG
//     gradients interpolate in sRGB, so they map to CGGradient directly.
//   • SVG `objectBoundingBox` gradients are resolved against each shape's
//     bounding box — including the ring's `rotate(-90)`, which turns its
//     gradient too, and the core's non-square box, which makes its radial
//     gradient elliptical.
//   • Drawing happens in a y-down space (the SVG/CSS convention), so design
//     coordinates are used verbatim.

import AppKit
import CoreGraphics

// MARK: - Output

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

let args = Array(CommandLine.arguments.dropFirst())
let outDir = URL(fileURLWithPath: args.first ?? "Sources/Aerie/Resources/Assets.xcassets/AppIcon.appiconset")
let aboutPNG = URL(fileURLWithPath: args.dropFirst().first ?? "Sources/Aerie/Resources/app-icon.png")
let aboutDimension = 512

// MARK: - Colour

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// OKLab, the space CSS interpolates oklch gradients in.
struct Lab { var l, a, b: Double }

func oklab(_ L: Double, _ C: Double, _ hDegrees: Double) -> Lab {
    let h = hDegrees * .pi / 180
    return Lab(l: L, a: C * cos(h), b: C * sin(h))
}

/// OKLab → gamma-encoded sRGB, clipped per channel.
func srgb(_ c: Lab) -> (Double, Double, Double) {
    let l_ = c.l + 0.3963377774 * c.a + 0.2158037573 * c.b
    let m_ = c.l - 0.1055613458 * c.a - 0.0638541728 * c.b
    let s_ = c.l - 0.0894841775 * c.a - 1.2914855480 * c.b
    let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
    let lin = (
        +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    )
    func encode(_ x: Double) -> Double {
        let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        return min(max(v, 0), 1)
    }
    return (encode(lin.0), encode(lin.1), encode(lin.2))
}

func color(_ lab: Lab, _ alpha: Double = 1) -> CGColor {
    let (r, g, b) = srgb(lab)
    return CGColor(colorSpace: sRGB, components: [r, g, b, alpha])!
}

func oklch(_ L: Double, _ C: Double, _ h: Double, _ alpha: Double = 1) -> CGColor {
    color(oklab(L, C, h), alpha)
}

func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r / 255, g / 255, b / 255, a])!
}

/// A CSS gradient between opaque oklch stops, expanded into dense sRGB stops
/// so CoreGraphics' sRGB interpolation follows CSS's OKLab path.
func cssGradient(_ stops: [(Lab, Double)], samples: Int = 32) -> CGGradient {
    var colors: [CGColor] = []
    var locations: [CGFloat] = []
    for i in 0...samples {
        let t = Double(i) / Double(samples)
        let k = stops.lastIndex { $0.1 <= t } ?? 0
        let (c0, p0) = stops[k]
        let (c1, p1) = stops[min(k + 1, stops.count - 1)]
        let u = p1 > p0 ? (t - p0) / (p1 - p0) : 0
        colors.append(color(Lab(l: c0.l + (c1.l - c0.l) * u,
                                a: c0.a + (c1.a - c0.a) * u,
                                b: c0.b + (c1.b - c0.b) * u)))
        locations.append(CGFloat(t))
    }
    return CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

/// A colour fading to CSS `transparent` over `[0, end]`. CSS interpolates
/// premultiplied, so the hue holds and only alpha ramps.
func fadeGradient(_ c: CGColor, alpha: Double, end: CGFloat) -> CGGradient {
    CGGradient(colorsSpace: sRGB,
               colors: [c.copy(alpha: alpha)!, c.copy(alpha: 0)!] as CFArray,
               locations: [0, end])!
}

func svgGradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

// MARK: - Palette (icon.jsx)

let gold = oklch(0.86, 0.155, 85)

// MARK: - Render

func renderIcon(dim: Int) -> Data {
    let ctx = CGContext(
        data: nil, width: dim, height: dim, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let D = CGFloat(dim)
    ctx.clear(CGRect(x: 0, y: 0, width: D, height: D))
    // y-down, like the design.
    ctx.translateBy(x: 0, y: D)
    ctx.scaleBy(x: 1, y: -1)

    // ---------- Squircle (CSS border-radius: 22.5%) ----------
    let box = CGRect(x: 0, y: 0, width: D, height: D)
    let squircle = CGPath(roundedRect: box, cornerWidth: D * 0.225, cornerHeight: D * 0.225, transform: nil)
    ctx.addPath(squircle)
    ctx.clip()

    // ---------- CSS background (bottom layer first) ----------
    // linear-gradient(155deg, oklch(0.20 0.02 70), oklch(0.07 0.012 275)).
    // The gradient line runs through the centre at 155° (0° = up) and is
    // |w·sin θ| + |h·cos θ| long.
    let theta = 155.0 * .pi / 180
    let dir = CGPoint(x: sin(theta), y: -cos(theta))          // y-down
    let half = (abs(sin(theta)) + abs(cos(theta))) * D / 2
    ctx.drawLinearGradient(
        cssGradient([(oklab(0.20, 0.02, 70), 0), (oklab(0.07, 0.012, 275), 1)]),
        start: CGPoint(x: D / 2 - dir.x * half, y: D / 2 - dir.y * half),
        end: CGPoint(x: D / 2 + dir.x * half, y: D / 2 + dir.y * half),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    /// CSS `radial-gradient(rx% ry% at cx% cy%, c 0%, transparent end%)`.
    func cssEllipse(rx: CGFloat, ry: CGFloat, cx: CGFloat, cy: CGFloat, color c: CGColor, alpha: Double, end: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: cx * D, y: cy * D)
        ctx.scaleBy(x: rx / ry, y: 1)
        ctx.drawRadialGradient(fadeGradient(c, alpha: alpha, end: end),
                               startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: ry * D, options: [])
        ctx.restoreGState()
    }
    // radial-gradient(90% 80% at 85% 100%, oklch(0.24 0.14 28 / 0.55) 0%, transparent 62%)
    cssEllipse(rx: 0.90, ry: 0.80, cx: 0.85, cy: 1.00, color: oklch(0.24, 0.14, 28), alpha: 0.55, end: 0.62)
    // radial-gradient(70% 60% at 50% 42%, oklch(0.30 0.055 70) 0%, transparent 62%)
    cssEllipse(rx: 0.70, ry: 0.60, cx: 0.50, cy: 0.42, color: oklch(0.30, 0.055, 70), alpha: 1, end: 0.62)

    // ---------- SVG layer (viewBox 0 0 100 100) ----------
    ctx.saveGState()
    ctx.scaleBy(x: D / 100, y: D / 100)

    func stroke(_ path: CGPath, _ c: CGColor, width: CGFloat, cap: CGLineCap = .butt, join: CGLineJoin = .miter) {
        ctx.addPath(path)
        ctx.setStrokeColor(c)
        ctx.setLineWidth(width)
        ctx.setLineCap(cap)
        ctx.setLineJoin(join)
        ctx.strokePath()
    }
    func circle(_ r: CGFloat, cx: CGFloat = 50, cy: CGFloat = 50) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
    }
    func poly(_ points: [(CGFloat, CGFloat)], closed: Bool) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        if closed { p.closeSubpath() }
        return p
    }

    // Etched HUD reticle — chamfered frame + corner ticks.
    stroke(poly([(17, 9), (72, 9), (83, 20), (83, 79), (30, 79), (17, 66)], closed: true),
           gold.copy(alpha: 0.16)!, width: 0.5)
    let ticks = CGMutablePath()
    ticks.addPath(poly([(11, 22), (11, 13), (20, 13)], closed: false))
    ticks.addPath(poly([(89, 78), (89, 87), (80, 87)], closed: false))
    stroke(ticks, gold.copy(alpha: 0.34)!, width: 0.7, cap: .round)

    // Measured tick rails down each side.
    let rails = CGMutablePath()
    for y: CGFloat in [32, 39, 46, 53, 60, 67] { rails.addLines(between: [CGPoint(x: 7, y: y), CGPoint(x: 11.5, y: y)]) }
    for y: CGFloat in [36, 44, 52, 60] { rails.addLines(between: [CGPoint(x: 89, y: y), CGPoint(x: 93, y: y)]) }
    stroke(rails, gold.copy(alpha: 0.22)!, width: 0.55)

    // Alloy housing: objectBoundingBox gradient (0,0)→(1,1) over the r=36 circle.
    ctx.saveGState()
    ctx.addPath(circle(36))
    ctx.clip()
    ctx.setAlpha(0.5)
    ctx.drawLinearGradient(
        svgGradient([(oklch(0.46, 0.03, 75), 0), (oklch(0.26, 0.02, 70), 0.5), (oklch(0.38, 0.03, 60), 1)]),
        start: CGPoint(x: 14, y: 14), end: CGPoint(x: 86, y: 86),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    stroke(circle(36), gold.copy(alpha: 0.22)!, width: 0.5)

    // Segmented energy ring — 12 dashes starting at 12 o'clock, clockwise.
    let ringArc = CGMutablePath()
    ringArc.addArc(center: CGPoint(x: 50, y: 50), radius: 30,
                   startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
    let segment = 2 * CGFloat.pi * 30 / 12
    let ringShape = ringArc
        .copy(dashingWithPhase: 0, lengths: [segment * 0.68, segment * 0.32])
        .copy(strokingWithWidth: 5.5, lineCap: .butt, lineJoin: .miter, miterLimit: 4)
    ctx.saveGState()
    ctx.addPath(ringShape)
    ctx.clip()
    // Bounding-box vector (0,0)→(0.7,1) on the circle's 20…80 box, then the
    // element's rotate(-90 50 50): (20,20)→(20,80), (62,80)→(80,38).
    ctx.drawLinearGradient(
        svgGradient([(oklch(0.94, 0.13, 90), 0), (oklch(0.78, 0.155, 70), 0.55), (oklch(0.62, 0.17, 34), 1)]),
        start: CGPoint(x: 20, y: 80), end: CGPoint(x: 80, y: 38),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Inner containment rings.
    stroke(circle(23), gold.copy(alpha: 0.5)!, width: 0.9)
    stroke(circle(20.5), oklch(0.62, 0.17, 34, 0.55), width: 0.6)

    // Radial struts through the ring.
    let struts = CGMutablePath()
    for a in stride(from: 0.0, to: 360.0, by: 60.0) {
        let rad = (a - 90) * .pi / 180
        struts.addLines(between: [
            CGPoint(x: 50 + cos(rad) * 20.5, y: 50 + sin(rad) * 20.5),
            CGPoint(x: 50 + cos(rad) * 34, y: 50 + sin(rad) * 34),
        ])
    }
    stroke(struts, oklch(0.20, 0.02, 70, 0.85), width: 1.6)

    // Core bloom (objectBoundingBox r=50% of the r=21 circle), opacity 0.55.
    ctx.saveGState()
    ctx.addPath(circle(21))
    ctx.clip()
    ctx.setAlpha(0.55)
    ctx.drawRadialGradient(
        svgGradient([(oklch(0.92, 0.145, 88, 0.85), 0), (oklch(0.80, 0.15, 72, 0.30), 0.45), (oklch(0.60, 0.15, 60, 0), 1)]),
        startCenter: CGPoint(x: 50, y: 50), startRadius: 0,
        endCenter: CGPoint(x: 50, y: 50), endRadius: 21, options: [])
    ctx.restoreGState()

    // Triangular reactor core. Its gradient (cx 46%, cy 40%, r 62%) lives in
    // the triangle's 24×21 bounding box, so it's an ellipse in user space.
    let core = poly([(50, 36.5), (62, 57.5), (38, 57.5)], closed: true)
    ctx.saveGState()
    ctx.addPath(core)
    ctx.clip()
    ctx.translateBy(x: 38, y: 36.5)
    ctx.scaleBy(x: 24, y: 21)
    ctx.drawRadialGradient(
        svgGradient([(oklch(0.99, 0.04, 90), 0), (oklch(0.92, 0.145, 88), 0.34),
                     (oklch(0.76, 0.155, 70), 0.72), (oklch(0.56, 0.15, 58), 1)]),
        startCenter: CGPoint(x: 0.46, y: 0.40), startRadius: 0,
        endCenter: CGPoint(x: 0.46, y: 0.40), endRadius: 0.62,
        options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    stroke(core, oklch(0.99, 0.05, 92, 0.8), width: 0.8)

    ctx.addPath(poly([(50, 42), (57.5, 55), (42.5, 55)], closed: true))
    ctx.setFillColor(oklch(1, 0, 0, 0.55))
    ctx.fillPath()
    ctx.addPath(circle(2.6, cy: 50.5))
    ctx.setFillColor(oklch(1, 0, 0, 0.95))
    ctx.fillPath()

    ctx.restoreGState()   // leave viewBox space

    // ---------- Top-edge glass highlight (top 34%) ----------
    ctx.drawLinearGradient(
        fadeGradient(rgba(255, 240, 215, 1), alpha: 0.09, end: 1),
        start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: D * 0.34), options: [])

    // ---------- Inset box-shadows (1px, no blur) ----------
    // `inset 0 1px 0 0 c` paints the part of the box not covered by the box
    // shifted down 1px — a hairline crescent along the top edge; `-1px` does
    // the same along the bottom.
    func insetEdge(dy: CGFloat, _ c: CGColor) {
        let shifted = CGPath(roundedRect: box.offsetBy(dx: 0, dy: dy),
                             cornerWidth: D * 0.225, cornerHeight: D * 0.225, transform: nil)
        let region = CGMutablePath()
        region.addPath(squircle)
        region.addPath(shifted)
        ctx.addPath(region)
        ctx.setFillColor(c)
        ctx.fillPath(using: .evenOdd)
    }
    insetEdge(dy: 1, rgba(255, 236, 205, 0.16))
    insetEdge(dy: -1, rgba(0, 0, 0, 0.5))

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Main

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for spec in specs {
    try renderIcon(dim: spec.dimension).write(to: outDir.appendingPathComponent(spec.filename))
    print("Wrote \(spec.filename) (\(spec.dimension)×\(spec.dimension))")
}
try renderIcon(dim: aboutDimension).write(to: aboutPNG)
print("Wrote \(aboutPNG.lastPathComponent) (\(aboutDimension)×\(aboutDimension))")
