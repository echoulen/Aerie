import SwiftUI
import AppKit
import QuartzCore

// The backdrop's moving layers — nebula clouds and parallax stars — live on
// Core Animation, not SwiftUI. A SwiftUI `repeatForever` re-renders its view
// every frame; for these full-window layers that meant re-rasterising (and
// waiting on GPU surfaces for) the whole backdrop 60–120 times a second, which
// held an idle window at ~40% CPU. Here each layer's contents are built once and
// the drift is a render-server animation that never touches the main thread.
// Both views sit on `LayerAnimationView` (epoch, resize, occlusion freeze).

// MARK: - Geometry (pure)

enum BackdropGeometry {
    struct Nebula: Equatable {
        let size: CGSize
        let from: CGPoint
        let to: CGPoint
    }

    /// Each nebula is painted on a 200%×200% background tile whose position
    /// swings between two keyframes, so its centre is `2·gradientPos − bgPos`
    /// of the box. Radii are % of the 2× tile.
    static func nebula(
        gradientAt g: CGPoint, radii: CGSize, bgFrom: CGPoint, bgTo: CGPoint, in size: CGSize
    ) -> Nebula {
        func centre(_ bg: CGPoint) -> CGPoint {
            CGPoint(x: (2 * g.x - bg.x) * size.width, y: (2 * g.y - bg.y) * size.height)
        }
        let rx = max(radii.width * 2 * size.width, 1)
        let ry = max(radii.height * 2 * size.height, 1)
        return Nebula(size: CGSize(width: rx * 2, height: ry * 2),
                      from: centre(bgFrom), to: centre(bgTo))
    }

    struct StarGrid: Equatable {
        /// The dot group's size: the view plus one loop of travel, so no edge
        /// is ever exposed mid-drift.
        let layerSize: CGSize
        /// Top-left of the group at the start of a loop — shifted back against
        /// the direction of travel.
        let origin: CGPoint
        let columns: Int
        let rows: Int
        /// Distance covered per loop: exactly `direction × tile`, so the tiling
        /// lands back on itself when the animation restarts — no visible jump.
        let travel: CGSize
        let duration: CFTimeInterval
    }

    static func starGrid(tile: CGFloat, direction: CGSize, speed: CGFloat, in size: CGSize) -> StarGrid {
        let travel = CGSize(width: direction.width * tile, height: direction.height * tile)
        let layerSize = CGSize(width: size.width + abs(travel.width),
                               height: size.height + abs(travel.height))
        return StarGrid(
            layerSize: layerSize,
            origin: CGPoint(x: travel.width < 0 ? 0 : -abs(travel.width),
                            y: travel.height < 0 ? 0 : -abs(travel.height)),
            columns: Int((layerSize.width / tile).rounded(.up)),
            rows: Int((layerSize.height / tile).rounded(.up)),
            travel: travel,
            duration: CFTimeInterval(hypot(travel.width, travel.height) / max(speed, 0.1))
        )
    }
}

// MARK: - Nebula

final class NebulaFieldView: LayerAnimationView {
    struct Cloud {
        let color: Color
        let alpha: Double
        let fade: CGFloat
        let gradientAt: CGPoint
        let radii: CGSize
        let bgFrom: CGPoint
        let bgTo: CGPoint
    }

    /// Burnt orange upper-right, violet lower-left, a faint cyan wash at the
    /// bottom — swimming against each other.
    static let clouds: [Cloud] = [
        // oklch(0.62 0.19 40)
        Cloud(color: Color(red: 0.876, green: 0.316, blue: 0.049), alpha: 0.30, fade: 0.62,
              gradientAt: CGPoint(x: 0.82, y: 0.08), radii: CGSize(width: 0.52, height: 0.44),
              bgFrom: CGPoint(x: 0.42, y: 0.44), bgTo: CGPoint(x: 0.58, y: 0.56)),
        // oklch(0.48 0.20 300)
        Cloud(color: Color(red: 0.446, green: 0.199, blue: 0.731), alpha: 0.34, fade: 0.64,
              gradientAt: CGPoint(x: 0.12, y: 0.84), radii: CGSize(width: 0.46, height: 0.52),
              bgFrom: CGPoint(x: 0.58, y: 0.56), bgTo: CGPoint(x: 0.42, y: 0.44)),
        // oklch(0.58 0.16 215)
        Cloud(color: Color(red: 0.0, green: 0.56, blue: 0.708), alpha: 0.18, fade: 0.66,
              gradientAt: CGPoint(x: 0.62, y: 0.96), radii: CGSize(width: 0.40, height: 0.40),
              bgFrom: CGPoint(x: 0.50, y: 0.48), bgTo: CGPoint(x: 0.50, y: 0.54)),
    ]

    /// One sweep of the nebula swim. The design's CSS uses 320s, which reads as
    /// static in the app; this is sped up so the motion is actually visible.
    static let swimSeconds: CFTimeInterval = 60
    static let swimKey = "aerie.nebula.swim"

    var intensity: Double = 1 {
        didSet { if intensity != oldValue { applyColors() } }
    }

    private(set) var cloudLayers: [CAGradientLayer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        cloudLayers = Self.clouds.map { cloud in
            let g = CAGradientLayer()
            g.type = .radial
            // A radial CAGradientLayer's end point is its radius in unit space:
            // (1, 1) inscribes the ellipse in the layer, like SwiftUI's
            // `EllipticalGradient` filling its frame.
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            g.locations = [0, NSNumber(value: Double(cloud.fade))]
            layer?.addSublayer(g)
            return g
        }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyColors() {
        for (g, cloud) in zip(cloudLayers, Self.clouds) {
            let base = NSColor(cloud.color)
            g.colors = [
                base.withAlphaComponent(min(cloud.alpha * intensity, 1)).cgColor,
                base.withAlphaComponent(0).cgColor,
            ]
        }
    }

    override func rebuild(size: CGSize, animate: Bool) {
        for (g, cloud) in zip(cloudLayers, Self.clouds) {
            let geo = BackdropGeometry.nebula(
                gradientAt: cloud.gradientAt, radii: cloud.radii,
                bgFrom: cloud.bgFrom, bgTo: cloud.bgTo, in: size)
            g.bounds = CGRect(origin: .zero, size: geo.size)
            g.position = geo.from
            g.removeAnimation(forKey: Self.swimKey)
            guard animate else { continue }
            let swim = CABasicAnimation(keyPath: "position")
            swim.fromValue = geo.from
            swim.toValue = geo.to
            swim.duration = Self.swimSeconds
            swim.autoreverses = true
            swim.repeatCount = .infinity
            swim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            swim.beginTime = beginTime(for: g)
            g.add(swim, forKey: Self.swimKey)
        }
    }
}

struct NebulaField: NSViewRepresentable {
    var intensity: Double
    var animated: Bool

    func makeNSView(context: Context) -> NebulaFieldView {
        let v = NebulaFieldView()
        v.intensity = intensity
        v.animated = animated
        return v
    }

    func updateNSView(_ v: NebulaFieldView, context: Context) {
        v.intensity = intensity
        v.animated = animated
    }
}

// MARK: - Stars

final class StarfieldView: LayerAnimationView {
    struct Dot {
        let size: CGFloat, tile: CGFloat, x: CGFloat, y: CGFloat, color: Color
    }

    /// Near stars — bigger, brighter, drifting fastest.
    static let near: [Dot] = [
        .init(size: 1.7, tile: 340, x: 0.20, y: 0.14, color: Color(red: 1, green: 244/255, blue: 226/255).opacity(0.95)),
        .init(size: 1.5, tile: 500, x: 0.72, y: 0.22, color: Color(red: 212/255, green: 232/255, blue: 1).opacity(0.90)),
        .init(size: 1.4, tile: 620, x: 0.88, y: 0.71, color: Color(red: 1, green: 222/255, blue: 190/255).opacity(0.88)),
        .init(size: 1.6, tile: 430, x: 0.42, y: 0.62, color: Color(red: 1, green: 236/255, blue: 210/255).opacity(0.85)),
    ]

    /// Far stars — finer, dimmer, crawling the same way more slowly.
    static let far: [Dot] = [
        .init(size: 1.0, tile: 260, x: 0.12, y: 0.46, color: Color(red: 226/255, green: 238/255, blue: 1).opacity(0.72)),
        .init(size: 1.0, tile: 300, x: 0.58, y: 0.88, color: Color(red: 1, green: 246/255, blue: 232/255).opacity(0.70)),
        .init(size: 0.9, tile: 180, x: 0.32, y: 0.30, color: Color(red: 1, green: 236/255, blue: 214/255).opacity(0.58)),
        .init(size: 1.1, tile: 540, x: 0.92, y: 0.38, color: Color(red: 210/255, green: 228/255, blue: 1).opacity(0.62)),
        .init(size: 0.8, tile: 220, x: 0.66, y: 0.08, color: Color(red: 1, green: 240/255, blue: 220/255).opacity(0.50)),
    ]

    /// Both layers head up-left at roughly the design's 1.7 : 1 drift angle;
    /// the far one is slower — parallax by speed. (The design's CSS sends the
    /// far layer the other way, which read as stars scattering, not a sky.)
    static let direction = CGSize(width: -2, height: -1)
    static let nearSpeed: CGFloat = 6
    static let farSpeed: CGFloat = 2.5

    static let driftKey = "aerie.stars.drift"
    static let twinkleKey = "aerie.stars.twinkle"

    let nearLayer = CALayer()
    let farLayer = CALayer()
    /// One group per dot spec, near first. Each is a grid of a single dot
    /// (nested replicators), so the GPU draws a handful of tiny quads rather
    /// than a window-sized texture.
    private(set) var dotGroupLayers: [CALayer] = []
    private var groups: [(dot: Dot, speed: CGFloat, group: CALayer, rows: CAReplicatorLayer, columns: CAReplicatorLayer)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        // `aerie-twinkle` holds the near layer between 0.92 and 0.62.
        nearLayer.opacity = 0.92
        farLayer.opacity = 0.8
        layer?.addSublayer(nearLayer)
        layer?.addSublayer(farLayer)
        for dot in Self.near { addGroup(dot, speed: Self.nearSpeed, to: nearLayer) }
        for dot in Self.far { addGroup(dot, speed: Self.farSpeed, to: farLayer) }
        dotGroupLayers = groups.map(\.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func addGroup(_ dot: Dot, speed: CGFloat, to parent: CALayer) {
        let star = CALayer()
        star.backgroundColor = NSColor(dot.color).cgColor
        star.frame = CGRect(x: dot.tile * dot.x - dot.size / 2, y: dot.tile * dot.y - dot.size / 2,
                            width: dot.size, height: dot.size)
        star.cornerRadius = dot.size / 2

        let columns = CAReplicatorLayer()
        columns.instanceTransform = CATransform3DMakeTranslation(dot.tile, 0, 0)
        columns.addSublayer(star)

        let rows = CAReplicatorLayer()
        rows.instanceTransform = CATransform3DMakeTranslation(0, dot.tile, 0)
        rows.addSublayer(columns)

        let group = CALayer()
        group.anchorPoint = .zero
        group.masksToBounds = true
        group.addSublayer(rows)
        parent.addSublayer(group)
        groups.append((dot, speed, group, rows, columns))
    }

    override func rebuild(size: CGSize, animate: Bool) {
        nearLayer.frame = CGRect(origin: .zero, size: size)
        farLayer.frame = CGRect(origin: .zero, size: size)

        for g in groups {
            let grid = BackdropGeometry.starGrid(
                tile: g.dot.tile, direction: Self.direction, speed: g.speed, in: size)
            g.group.bounds = CGRect(origin: .zero, size: grid.layerSize)
            g.group.position = grid.origin
            g.rows.frame = g.group.bounds
            g.rows.instanceCount = grid.rows
            g.columns.frame = g.group.bounds
            g.columns.instanceCount = grid.columns

            g.group.removeAnimation(forKey: Self.driftKey)
            guard animate else { continue }
            let drift = CABasicAnimation(keyPath: "position")
            drift.fromValue = grid.origin
            drift.toValue = CGPoint(x: grid.origin.x + grid.travel.width,
                                    y: grid.origin.y + grid.travel.height)
            drift.duration = grid.duration
            drift.repeatCount = .infinity
            drift.beginTime = beginTime(for: g.group)
            g.group.add(drift, forKey: Self.driftKey)
        }

        nearLayer.removeAnimation(forKey: Self.twinkleKey)
        if animate {
            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = 0.92
            twinkle.toValue = 0.62
            twinkle.duration = 5.5
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            twinkle.beginTime = beginTime(for: nearLayer)
            nearLayer.add(twinkle, forKey: Self.twinkleKey)
        }
    }
}

struct Starfield: NSViewRepresentable {
    var animated: Bool

    func makeNSView(context: Context) -> StarfieldView {
        let v = StarfieldView()
        v.animated = animated
        return v
    }

    func updateNSView(_ v: StarfieldView, context: Context) {
        v.animated = animated
    }
}
