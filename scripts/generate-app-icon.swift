#!/usr/bin/env swift
import AppKit
import CoreGraphics

struct IconSpec {
    let size: Int
    let scale: Int
    var dimension: Int { size * scale }
    var filename: String { scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png" }
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

func renderIcon(dimension: Int) -> Data {
    let rect = CGRect(x: 0, y: 0, width: dimension, height: dimension)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil,
                        width: dimension, height: dimension,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Clear:
    ctx.clear(rect)

    // Squircle background:
    let inset: CGFloat = CGFloat(dimension) * 0.04
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let radius: CGFloat = CGFloat(dimension) * 0.23
    let path = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0x0b/255, green: 0x0b/255, blue: 0x10/255, alpha: 1))
    ctx.fillPath()

    // Clip subsequent drawing to the squircle so rings/orb don't bleed past
    // the rounded corners.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    // Radar rings:
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let baseR = CGFloat(dimension) * 0.34
    let ringSpecs: [(Int, CGFloat)] = [(0, 0.18), (1, 0.10), (2, 0.05)]
    for (i, alpha) in ringSpecs {
        let r = baseR + CGFloat(i) * (CGFloat(dimension) * 0.12)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        ctx.setLineWidth(max(1, CGFloat(dimension) * 0.012))
        ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
    }

    // Amber orb (radial gradient):
    let orbR = CGFloat(dimension) * 0.20
    let orbRect = CGRect(x: center.x - orbR, y: center.y - orbR, width: orbR*2, height: orbR*2)
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.98, green: 0.75, blue: 0.30, alpha: 1),     // amber
            CGColor(red: 0.62, green: 0.45, blue: 0.18, alpha: 1),     // mid
            CGColor(red: 0.32, green: 0.23, blue: 0.10, alpha: 1),     // rim
        ] as CFArray,
        locations: [0.0, 0.7, 1.0]
    )!
    let highlight = CGPoint(x: center.x - orbR * 0.30, y: center.y + orbR * 0.40)  // CG y is flipped
    ctx.saveGState()
    ctx.addEllipse(in: orbRect)
    ctx.clip()
    ctx.drawRadialGradient(gradient, startCenter: highlight, startRadius: 0,
                           endCenter: center, endRadius: orbR,
                           options: [])
    ctx.restoreGState()

    // Small bright highlight at top-left of the orb (CG y flipped so +y = up).
    let hlR = orbR * 0.18
    let hlCenter = CGPoint(x: center.x - orbR * 0.35, y: center.y + orbR * 0.30)
    let hlGradient = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.9),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: hlCenter.x - hlR, y: hlCenter.y - hlR, width: hlR*2, height: hlR*2))
    ctx.clip()
    ctx.drawRadialGradient(hlGradient, startCenter: hlCenter, startRadius: 0,
                           endCenter: hlCenter, endRadius: hlR,
                           options: [])
    ctx.restoreGState()

    // Restore squircle clip:
    ctx.restoreGState()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])!
}

for spec in specs {
    let data = renderIcon(dimension: spec.dimension)
    let url = outDir.appendingPathComponent(spec.filename)
    try data.write(to: url)
    print("Wrote \(url.lastPathComponent)")
}
