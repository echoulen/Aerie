import SwiftUI
import AppKit
import QuartzCore

// The backdrop's planets — a big banded gas giant (Jupiter) cropped by the
// lower-right corner, a hazy Venus upper-left and a small ringed Uranus up top.
// Like the nebulae and stars they live on Core Animation: each planet is painted
// once into a bitmap per size (Core Graphics, no image assets), then crosses
// the view on a render-server animation — off one edge, a spell out of sight,
// and back in from the other.

// MARK: - Art (pure)

enum PlanetArt {
    enum Kind: CaseIterable { case jupiter, venus, uranus }

    /// Canvas side ÷ planet diameter — room for the halo (and Uranus's rings)
    /// around the disc.
    static func canvasRatio(_ kind: Kind) -> CGFloat {
        switch kind {
        case .jupiter: return 1.2
        case .venus: return 1.7
        case .uranus: return 2.0
        }
    }

    /// Paints `kind` at `diameter` points onto a square, transparent canvas
    /// `diameter × canvasRatio` points wide, centred.
    static func image(_ kind: Kind, diameter: CGFloat, scale: CGFloat) -> CGImage? {
        let side = diameter * canvasRatio(kind)
        let px = Int((side * scale).rounded(.up))
        guard px > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // Top-left origin, like the rest of the backdrop maths.
        ctx.translateBy(x: 0, y: side)
        ctx.scaleBy(x: 1, y: -1)

        let c = CGPoint(x: side / 2, y: side / 2)
        let r = diameter / 2
        switch kind {
        case .jupiter: paintJupiter(ctx, c, r)
        case .venus: paintVenus(ctx, c, r)
        case .uranus: paintUranus(ctx, c, r)
        }
        return ctx.makeImage()
    }

    // MARK: Planets

    private static func paintJupiter(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        halo(ctx, c, r, outer: 1.16, color: rgb(0.96, 0.78, 0.56), alpha: 0.22)
        disc(ctx, c, r, base: rgb(0.91, 0.83, 0.69)) {
            let cream: RGB = (0.97, 0.93, 0.84), tan: RGB = (0.80, 0.60, 0.42)
            let rust: RGB = (0.70, 0.43, 0.27), brown: RGB = (0.52, 0.36, 0.26)
            let seam: RGB = (0.55, 0.30, 0.20)
            bands(ctx, c, r, tilt: -0.2, [
                (-0.86, 0.16, brown, 0.85),
                (-0.60, 0.11, tan, 0.80),
                (-0.33, 0.14, rust, 0.95),
                (-0.38, 0.025, seam, 0.80),
                (-0.06, 0.11, cream, 0.85),
                (0.20, 0.15, rust, 0.95),
                (0.26, 0.025, seam, 0.80),
                (0.47, 0.09, tan, 0.70),
                (0.68, 0.10, brown, 0.60),
                (0.90, 0.14, (0.45, 0.32, 0.25), 0.90),
            ]) {
                // The Great Red Spot, on the south edge of its belt.
                blob(ctx, CGPoint(x: c.x - 0.40 * r, y: c.y + 0.29 * r),
                     rx: 0.19 * r, ry: 0.105 * r,
                     inner: rgb(0.80, 0.34, 0.20, 0.95), outer: rgb(0.86, 0.55, 0.38, 0))
            }
            shade(ctx, c, r, depth: 0.88)
        }
    }

    private static func paintVenus(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        halo(ctx, c, r, outer: 1.55, color: rgb(1.0, 0.90, 0.66), alpha: 0.32)
        disc(ctx, c, r, base: rgb(0.93, 0.84, 0.62)) {
            bands(ctx, c, r, tilt: 0.35, [
                (-0.45, 0.30, (0.99, 0.94, 0.80), 0.55),
                (0.05, 0.28, (0.84, 0.70, 0.46), 0.40),
                (0.50, 0.24, (0.99, 0.93, 0.76), 0.45),
            ])
            shade(ctx, c, r, depth: 0.78)
        }
    }

    private static func paintUranus(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        let tilt: CGFloat = -1.15
        // Back half of the rings first, then the disc over it, then the front half.
        rings(ctx, c, r, tilt: tilt, front: false)
        halo(ctx, c, r, outer: 1.25, color: rgb(0.62, 0.90, 0.95), alpha: 0.22)
        disc(ctx, c, r, base: rgb(0.62, 0.86, 0.89)) {
            bands(ctx, c, r, tilt: tilt + .pi / 2, [
                (-0.55, 0.30, (0.78, 0.94, 0.95), 0.40),
                (0.55, 0.30, (0.48, 0.76, 0.82), 0.35),
            ])
            shade(ctx, c, r, depth: 0.82)
        }
        rings(ctx, c, r, tilt: tilt, front: true)
    }

    // MARK: Brushes

    private typealias RGB = (CGFloat, CGFloat, CGFloat)

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: colors as CFArray, locations: locations)
    }

    /// Fills the disc with `base`, then runs `body` clipped to it.
    private static func disc(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat,
                             base: CGColor, _ body: () -> Void) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        ctx.setFillColor(base)
        ctx.fill(rect)
        body()
        ctx.restoreGState()
    }

    /// Soft-edged horizontal cloud bands, rotated by `tilt` radians about the
    /// centre. Each band is (centre y, half-height) in units of `r`, an RGB
    /// triple and an alpha. `extra` draws in the same rotated frame.
    private static func bands(
        _ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, tilt: CGFloat,
        _ specs: [(CGFloat, CGFloat, RGB, CGFloat)],
        extra: () -> Void = {}
    ) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: tilt)
        ctx.translateBy(x: -c.x, y: -c.y)
        for (y, h, rgbv, a) in specs {
            let color = rgb(rgbv.0, rgbv.1, rgbv.2, a)
            let clear = rgb(rgbv.0, rgbv.1, rgbv.2, 0)
            guard let g = gradient([clear, color, clear], [0, 0.5, 1]) else { continue }
            let top = CGPoint(x: c.x, y: c.y + (y - h) * r)
            let bottom = CGPoint(x: c.x, y: c.y + (y + h) * r)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: c.x - 1.5 * r, y: top.y, width: 3 * r, height: bottom.y - top.y))
            ctx.drawLinearGradient(g, start: top, end: bottom, options: [])
            ctx.restoreGState()
        }
        extra()
        ctx.restoreGState()
    }

    /// A soft elliptical spot.
    private static func blob(_ ctx: CGContext, _ at: CGPoint, rx: CGFloat, ry: CGFloat,
                             inner: CGColor, outer: CGColor) {
        guard let g = gradient([inner, outer], [0, 1]) else { return }
        ctx.saveGState()
        ctx.translateBy(x: at.x, y: at.y)
        ctx.scaleBy(x: 1, y: ry / rx)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: rx, options: [])
        ctx.restoreGState()
    }

    /// Lit from above and a little to the right (the burnt-orange nebula's
    /// side): a faint highlight fading into a dark terminator on the lower
    /// left. `depth` is the night side's opacity.
    private static func shade(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, depth: CGFloat) {
        let light = CGPoint(x: c.x + 0.28 * r, y: c.y - 0.52 * r)
        guard let g = gradient(
            [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0), rgb(0, 0, 0, depth * 0.3), rgb(0, 0, 0, depth)],
            [0, 0.35, 0.72, 1]
        ) else { return }
        // Two-point gradient: rings run from the light point out to the limb,
        // so the terminator hugs the disc instead of cutting across it.
        ctx.drawRadialGradient(g, startCenter: light, startRadius: 0,
                               endCenter: c, endRadius: r,
                               options: [.drawsAfterEndLocation])
    }

    /// Atmospheric glow from the limb out to `outer × r`.
    private static func halo(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat,
                             outer: CGFloat, color: CGColor, alpha: CGFloat) {
        guard let g = gradient([color.copy(alpha: alpha)!, color.copy(alpha: 0)!], [0, 1])
        else { return }
        ctx.drawRadialGradient(g, startCenter: c, startRadius: r * 0.96,
                               endCenter: c, endRadius: r * outer, options: [])
    }

    /// Uranus's thin rings, as tilted ellipses. `front` draws the half that
    /// passes in front of the disc; otherwise the half behind it.
    private static func rings(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat,
                              tilt: CGFloat, front: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: tilt)
        ctx.clip(to: CGRect(x: -2 * r, y: front ? 0 : -2 * r, width: 4 * r, height: 2 * r))
        for (radius, width, alpha) in [(1.48, 0.05, 0.30), (1.62, 0.025, 0.45), (1.76, 0.04, 0.60)]
            as [(CGFloat, CGFloat, CGFloat)] {
            ctx.setStrokeColor(rgb(0.82, 0.94, 0.96, alpha))
            ctx.setLineWidth(width * r)
            ctx.strokeEllipse(in: CGRect(x: -radius * r, y: -radius * r * 0.26,
                                         width: 2 * radius * r, height: 2 * radius * r * 0.26))
        }
        ctx.restoreGState()
    }
}

// MARK: - Planet field

extension BackdropGeometry {
    struct Crossing: Equatable {
        /// Just off the entry edge — the layer is wholly outside the view.
        let from: CGPoint
        /// Past the exit edge by `gap` seconds of travel, so the planet stays
        /// off screen for a while before the loop brings it back in.
        let to: CGPoint
        let duration: CFTimeInterval
        /// Seconds into the loop at which the planet sits on its home point —
        /// so a fresh window opens with the composed sky, not an empty one.
        let homeOffset: CFTimeInterval
    }

    /// A straight pass along `direction` through `home`, for a layer
    /// `halfSide` points from centre to edge.
    static func crossing(home: CGPoint, halfSide: CGFloat, direction: CGSize,
                         speed: CGFloat, gap: CFTimeInterval, in size: CGSize) -> Crossing {
        let length = max(hypot(direction.width, direction.height), .ulpOfOne)
        let d = CGVector(dx: direction.width / length, dy: direction.height / length)
        // Distance along `d` (from home) at which the layer's box is wholly
        // outside the view, per axis; ±∞ on an axis it doesn't move along.
        func exit(_ p: CGFloat, _ v: CGFloat, _ extent: CGFloat) -> (enter: CGFloat, leave: CGFloat) {
            guard v != 0 else { return (-.infinity, .infinity) }
            let low = (-halfSide - p) / v, high = (extent + halfSide - p) / v
            return (min(low, high), max(low, high))
        }
        let x = exit(home.x, d.dx, size.width)
        let y = exit(home.y, d.dy, size.height)
        let enter = max(x.enter, y.enter)
        let leave = min(x.leave, y.leave) + speed * CGFloat(gap)
        func at(_ t: CGFloat) -> CGPoint { CGPoint(x: home.x + t * d.dx, y: home.y + t * d.dy) }
        let speed = max(speed, 0.1)
        return Crossing(from: at(enter), to: at(leave),
                        duration: CFTimeInterval((leave - enter) / speed),
                        homeOffset: CFTimeInterval(-enter / speed))
    }
}

final class PlanetFieldView: LayerAnimationView {
    struct Planet {
        let kind: PlanetArt.Kind
        /// Where the planet sits when still (Reduce Motion) and at the start of
        /// its pass, as a fraction of the view.
        let centre: CGPoint
        /// Diameter, as a fraction of the view's shorter side.
        let diameter: CGFloat
        let opacity: Float
        /// Points per second. Bigger (nearer) planets move faster — parallax.
        let speed: CGFloat
        /// Seconds spent off screen between passes.
        let gap: CFTimeInterval
    }

    /// One big, two small: Jupiter by the lower-right corner, Venus upper-left,
    /// Uranus up top by the burnt-orange nebula.
    static let planets: [Planet] = [
        Planet(kind: .jupiter, centre: CGPoint(x: 0.88, y: 0.82), diameter: 0.38,
               opacity: 0.92, speed: 9, gap: 40),
        Planet(kind: .venus, centre: CGPoint(x: 0.09, y: 0.22), diameter: 0.052,
               opacity: 0.88, speed: 6, gap: 25),
        Planet(kind: .uranus, centre: CGPoint(x: 0.71, y: 0.15), diameter: 0.034,
               opacity: 0.85, speed: 4.5, gap: 30),
    ]

    /// Same heading as the starfield: up-left.
    static let direction = StarfieldView.direction
    static let driftKey = "aerie.planets.drift"

    private(set) var planetLayers: [CALayer] = []
    /// (diameter, scale) each layer's bitmap was painted at — a rebuild that
    /// doesn't change it keeps the bitmap.
    private var painted: [(CGFloat, CGFloat)?] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        planetLayers = Self.planets.map { planet in
            let l = CALayer()
            l.opacity = planet.opacity
            // Parallel lanes can still overlap: the bigger, nearer planet
            // passes in front.
            l.zPosition = planet.diameter
            layer?.addSublayer(l)
            return l
        }
        painted = Array(repeating: nil, count: Self.planets.count)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Moved to a display with a different scale — repaint the bitmaps.
        invalidateLayers()
    }

    override func rebuild(size: CGSize, animate: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        let shorter = min(size.width, size.height)
        for (i, (l, planet)) in zip(planetLayers, Self.planets).enumerated() {
            let diameter = (planet.diameter * shorter).rounded()
            if painted[i].map({ $0 != (diameter, scale) }) ?? true {
                l.contents = PlanetArt.image(planet.kind, diameter: diameter, scale: scale)
                painted[i] = (diameter, scale)
            }
            let side = diameter * PlanetArt.canvasRatio(planet.kind)
            let home = CGPoint(x: planet.centre.x * size.width, y: planet.centre.y * size.height)
            l.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            l.position = home

            l.removeAnimation(forKey: Self.driftKey)
            guard animate else { continue }
            let pass = BackdropGeometry.crossing(
                home: home, halfSide: side / 2, direction: Self.direction,
                speed: planet.speed, gap: planet.gap, in: size)
            let drift = CABasicAnimation(keyPath: "position")
            drift.fromValue = pass.from
            drift.toValue = pass.to
            drift.duration = pass.duration
            drift.repeatCount = .infinity
            drift.beginTime = beginTime(for: l)
            drift.timeOffset = pass.homeOffset
            l.add(drift, forKey: Self.driftKey)
        }
    }
}

struct PlanetField: NSViewRepresentable {
    var animated: Bool

    func makeNSView(context: Context) -> PlanetFieldView {
        let v = PlanetFieldView()
        v.animated = animated
        return v
    }

    func updateNSView(_ v: PlanetFieldView, context: Context) {
        v.animated = animated
    }
}
