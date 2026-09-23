import SwiftUI
import AppKit
import QuartzCore

// The backdrop's nebula clouds and parallax stars live on Core Animation, not
// SwiftUI: each layer's contents are built once and never re-rasterised. The
// field is static — nothing drifts — so the render server composites a handful
// of cached layers and otherwise leaves the window alone. Both views sit on
// `LayerAnimationView` (resize, contents scale, no hit-testing).

// MARK: - Geometry (pure)

enum BackdropGeometry {
    struct Nebula: Equatable {
        let size: CGSize
        let centre: CGPoint
    }

    /// Each nebula is painted on a 200%×200% background tile at `bgPos`, so its
    /// centre is `2·gradientPos − bgPos` of the box. Radii are % of the 2× tile.
    static func nebula(
        gradientAt g: CGPoint, radii: CGSize, bgAt bg: CGPoint, in size: CGSize
    ) -> Nebula {
        let rx = max(radii.width * 2 * size.width, 1)
        let ry = max(radii.height * 2 * size.height, 1)
        return Nebula(size: CGSize(width: rx * 2, height: ry * 2),
                      centre: CGPoint(x: (2 * g.x - bg.x) * size.width, y: (2 * g.y - bg.y) * size.height))
    }

    struct StarGrid: Equatable {
        let columns: Int
        let rows: Int
    }

    /// Enough tiles of `tile` to cover `size`.
    static func starGrid(tile: CGFloat, in size: CGSize) -> StarGrid {
        StarGrid(columns: Int((size.width / tile).rounded(.up)),
                 rows: Int((size.height / tile).rounded(.up)))
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
        let bgAt: CGPoint
    }

    /// Burnt orange upper-right, violet lower-left, a faint cyan wash at the
    /// bottom.
    static let clouds: [Cloud] = [
        // oklch(0.62 0.19 40)
        Cloud(color: Color(red: 0.876, green: 0.316, blue: 0.049), alpha: 0.30, fade: 0.62,
              gradientAt: CGPoint(x: 0.82, y: 0.08), radii: CGSize(width: 0.52, height: 0.44),
              bgAt: CGPoint(x: 0.42, y: 0.44)),
        // oklch(0.48 0.20 300)
        Cloud(color: Color(red: 0.446, green: 0.199, blue: 0.731), alpha: 0.34, fade: 0.64,
              gradientAt: CGPoint(x: 0.12, y: 0.84), radii: CGSize(width: 0.46, height: 0.52),
              bgAt: CGPoint(x: 0.58, y: 0.56)),
        // oklch(0.58 0.16 215)
        Cloud(color: Color(red: 0.0, green: 0.56, blue: 0.708), alpha: 0.18, fade: 0.66,
              gradientAt: CGPoint(x: 0.62, y: 0.96), radii: CGSize(width: 0.40, height: 0.40),
              bgAt: CGPoint(x: 0.50, y: 0.48)),
    ]

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
                gradientAt: cloud.gradientAt, radii: cloud.radii, bgAt: cloud.bgAt, in: size)
            g.bounds = CGRect(origin: .zero, size: geo.size)
            g.position = geo.centre
        }
    }
}

struct NebulaField: NSViewRepresentable {
    var intensity: Double

    func makeNSView(context: Context) -> NebulaFieldView {
        let v = NebulaFieldView()
        v.intensity = intensity
        return v
    }

    func updateNSView(_ v: NebulaFieldView, context: Context) {
        v.intensity = intensity
    }
}

// MARK: - Stars

final class StarfieldView: LayerAnimationView {
    struct Dot {
        let size: CGFloat, tile: CGFloat, x: CGFloat, y: CGFloat, color: Color
    }

    /// Near stars — bigger, brighter.
    static let near: [Dot] = [
        .init(size: 1.7, tile: 340, x: 0.20, y: 0.14, color: Color(red: 1, green: 244/255, blue: 226/255).opacity(0.95)),
        .init(size: 1.5, tile: 500, x: 0.72, y: 0.22, color: Color(red: 212/255, green: 232/255, blue: 1).opacity(0.90)),
        .init(size: 1.4, tile: 620, x: 0.88, y: 0.71, color: Color(red: 1, green: 222/255, blue: 190/255).opacity(0.88)),
        .init(size: 1.6, tile: 430, x: 0.42, y: 0.62, color: Color(red: 1, green: 236/255, blue: 210/255).opacity(0.85)),
    ]

    /// Far stars — finer, dimmer.
    static let far: [Dot] = [
        .init(size: 1.0, tile: 260, x: 0.12, y: 0.46, color: Color(red: 226/255, green: 238/255, blue: 1).opacity(0.72)),
        .init(size: 1.0, tile: 300, x: 0.58, y: 0.88, color: Color(red: 1, green: 246/255, blue: 232/255).opacity(0.70)),
        .init(size: 0.9, tile: 180, x: 0.32, y: 0.30, color: Color(red: 1, green: 236/255, blue: 214/255).opacity(0.58)),
        .init(size: 1.1, tile: 540, x: 0.92, y: 0.38, color: Color(red: 210/255, green: 228/255, blue: 1).opacity(0.62)),
        .init(size: 0.8, tile: 220, x: 0.66, y: 0.08, color: Color(red: 1, green: 240/255, blue: 220/255).opacity(0.50)),
    ]

    let nearLayer = CALayer()
    let farLayer = CALayer()
    /// One group per dot spec, near first. Each is a grid of a single dot
    /// (nested replicators), so the GPU draws a handful of tiny quads rather
    /// than a window-sized texture.
    private(set) var dotGroupLayers: [CALayer] = []
    private var groups: [(dot: Dot, group: CALayer, rows: CAReplicatorLayer, columns: CAReplicatorLayer)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        nearLayer.opacity = 0.92
        farLayer.opacity = 0.8
        layer?.addSublayer(nearLayer)
        layer?.addSublayer(farLayer)
        for dot in Self.near { addGroup(dot, to: nearLayer) }
        for dot in Self.far { addGroup(dot, to: farLayer) }
        dotGroupLayers = groups.map(\.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func addGroup(_ dot: Dot, to parent: CALayer) {
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
        groups.append((dot, group, rows, columns))
    }

    override func rebuild(size: CGSize, animate: Bool) {
        nearLayer.frame = CGRect(origin: .zero, size: size)
        farLayer.frame = CGRect(origin: .zero, size: size)

        for g in groups {
            let grid = BackdropGeometry.starGrid(tile: g.dot.tile, in: size)
            g.group.bounds = CGRect(origin: .zero, size: size)
            g.group.position = .zero
            g.rows.frame = g.group.bounds
            g.rows.instanceCount = grid.rows
            g.columns.frame = g.group.bounds
            g.columns.instanceCount = grid.columns
        }
    }
}

struct Starfield: NSViewRepresentable {
    func makeNSView(context: Context) -> StarfieldView { StarfieldView() }
    func updateNSView(_ v: StarfieldView, context: Context) {}
}
