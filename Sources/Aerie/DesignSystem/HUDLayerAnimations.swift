import SwiftUI
import AppKit
import QuartzCore

// The HUD's small persistent animations — breathing dots, the brand mark's
// glow, spinners, the progress sweep, the console caret — on Core Animation.
// Each is a `LayerAnimationView` subclass plus a thin `NSViewRepresentable`
// facade; the SwiftUI components that used to own a `repeatForever` now just
// place the facade at the same size. See `LayerAnimationView` for the shared
// mechanics (epoch, resize, occlusion freeze).

private func circlePath(in rect: CGRect) -> CGPath { CGPath(ellipseIn: rect, transform: nil) }

private func loop(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval,
                  autoreverses: Bool = false, ease: Bool = false) -> CABasicAnimation {
    let a = CABasicAnimation(keyPath: keyPath)
    a.fromValue = from
    a.toValue = to
    a.duration = duration
    a.autoreverses = autoreverses
    a.repeatCount = .infinity
    a.timingFunction = CAMediaTimingFunction(name: ease ? .easeInEaseOut : .linear)
    return a
}

// MARK: - Breathing dot

/// A small filled circle with a glow that breathes (opacity + scale). The
/// titlebar's LIVE dot and the review screen's arc pill both use it.
final class BreathingDotView: LayerAnimationView {
    struct Style: Equatable {
        var color: Color
        var glow: Color?
        var glowRadius: CGFloat = 5
        /// One full breath (in and out).
        var period: Double = 1.8
        var minOpacity: Float = 0.55
        var minScale: CGFloat = 0.82
    }

    static let opacityKey = "aerie.dot.opacity"
    static let scaleKey = "aerie.dot.scale"

    var style: Style {
        didSet { if style != oldValue { applyStyle(); invalidateLayers() } }
    }
    let dot = CALayer()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        layer?.masksToBounds = false   // the glow spills past the dot
        layer?.addSublayer(dot)
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyStyle() {
        dot.backgroundColor = NSColor(style.color).cgColor
        dot.shadowColor = style.glow.map { NSColor($0).cgColor }
        dot.shadowOpacity = style.glow == nil ? 0 : 1
        dot.shadowRadius = style.glowRadius
        dot.shadowOffset = .zero
    }

    override func rebuild(size: CGSize, animate: Bool) {
        dot.bounds = CGRect(origin: .zero, size: size)
        dot.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dot.cornerRadius = min(size.width, size.height) / 2
        dot.removeAnimation(forKey: Self.opacityKey)
        dot.removeAnimation(forKey: Self.scaleKey)
        guard animate else { return }
        let half = style.period / 2
        let opacity = loop("opacity", from: 1, to: style.minOpacity, duration: half, autoreverses: true, ease: true)
        let scale = loop("transform.scale", from: 1, to: style.minScale, duration: half, autoreverses: true, ease: true)
        opacity.beginTime = beginTime(for: dot)
        scale.beginTime = beginTime(for: dot)
        dot.add(opacity, forKey: Self.opacityKey)
        dot.add(scale, forKey: Self.scaleKey)
    }
}

struct BreathingDot: NSViewRepresentable {
    var style: BreathingDotView.Style
    var animated: Bool

    func makeNSView(context: Context) -> BreathingDotView {
        let v = BreathingDotView(style: style)
        v.animated = animated
        return v
    }

    func updateNSView(_ v: BreathingDotView, context: Context) {
        v.style = style
        v.animated = animated
    }
}

// MARK: - Brand mark

/// The white-hot gold orb with a breathing glow (`styles.css .brand-mark`).
/// The glow is a shadow whose radius animates 5 ↔ 10 — the one property that
/// was most expensive to animate in SwiftUI, where a changing shadow radius
/// re-blurs every frame.
final class BrandMarkView: LayerAnimationView {
    static let glowKey = "aerie.brand.glow"

    /// A filled disc under the orb whose shadow is the glow. It has real
    /// content (not just a `shadowPath`) so the shadow also renders in
    /// offscreen `renderInContext` paths such as snapshot tests; it's filled
    /// in the orb's rim colour so nothing bright peeks past the orb's
    /// anti-aliased edge.
    private let glow = CAShapeLayer()
    private let orb = CAGradientLayer()

    // oklch(0.55 0.15 60) / oklch(0.26 0.06 60)
    private static let mid = NSColor(red: 0.683, green: 0.339, blue: 0.0, alpha: 1)
    private static let rim = NSColor(red: 0.221, green: 0.108, blue: 0.003, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.masksToBounds = false
        glow.fillColor = Self.rim.cgColor
        glow.shadowColor = NSColor(AerieColor.amberGlow).cgColor
        glow.shadowOpacity = 1
        glow.shadowOffset = .zero
        glow.shadowRadius = 5
        orb.type = .radial
        orb.colors = [NSColor.white.cgColor, NSColor(AerieColor.amber).cgColor, Self.mid.cgColor, Self.rim.cgColor]
        orb.locations = [0, 0.38, 0.72, 1]
        orb.startPoint = CGPoint(x: 0.5, y: 0.5)
        orb.endPoint = CGPoint(x: 1, y: 1)
        orb.masksToBounds = true
        layer?.addSublayer(glow)
        layer?.addSublayer(orb)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func rebuild(size: CGSize, animate: Bool) {
        let rect = CGRect(origin: .zero, size: size)
        glow.frame = rect
        glow.path = circlePath(in: rect)
        glow.shadowPath = glow.path
        orb.frame = rect
        orb.cornerRadius = min(size.width, size.height) / 2
        glow.removeAnimation(forKey: Self.glowKey)
        guard animate else { return }
        let breathe = loop("shadowRadius", from: 5, to: 10, duration: 1.6, autoreverses: true, ease: true)
        breathe.beginTime = beginTime(for: glow)
        glow.add(breathe, forKey: Self.glowKey)
    }
}

struct BrandMarkLayer: NSViewRepresentable {
    var animated: Bool
    func makeNSView(context: Context) -> BrandMarkView {
        let v = BrandMarkView()
        v.animated = animated
        return v
    }
    func updateNSView(_ v: BrandMarkView, context: Context) { v.animated = animated }
}

// MARK: - Arc spinner

/// A stroked circle (or arc of one) that rotates forever — the inline
/// `.spinner`, the dialog spinner, and the About screen's slow dashed ring.
final class ArcSpinnerView: LayerAnimationView {
    struct Style: Equatable {
        var color: Color
        var lineWidth: CGFloat = 2
        /// Visible portion of the circle, 0...1 from 3 o'clock clockwise.
        var trimTo: CGFloat = 1
        /// Static rotation applied before the spin, in degrees.
        var startAngle: CGFloat = 0
        /// Seconds per revolution.
        var duration: Double = 0.7
        var shadow: Color? = nil
        var shadowRadius: CGFloat = 2
        var dash: [CGFloat]? = nil
        /// Diameter of the stroked circle; nil = fill the view.
        var diameter: CGFloat? = nil
    }

    static let spinKey = "aerie.spinner.spin"

    var style: Style {
        didSet { if style != oldValue { applyStyle(); invalidateLayers() } }
    }
    let arc = CAShapeLayer()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        layer?.masksToBounds = false
        arc.fillColor = nil
        arc.shadowOffset = .zero
        layer?.addSublayer(arc)
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyStyle() {
        arc.strokeColor = NSColor(style.color).cgColor
        arc.lineWidth = style.lineWidth
        arc.strokeEnd = style.trimTo
        arc.shadowColor = style.shadow.map { NSColor($0).cgColor }
        arc.shadowOpacity = style.shadow == nil ? 0 : 1
        arc.shadowRadius = style.shadowRadius
        arc.lineDashPattern = style.dash?.map { NSNumber(value: Double($0)) }
    }

    override func rebuild(size: CGSize, animate: Bool) {
        let d = style.diameter ?? min(size.width, size.height)
        arc.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        arc.position = CGPoint(x: size.width / 2, y: size.height / 2)
        arc.path = circlePath(in: arc.bounds.insetBy(dx: style.lineWidth / 2, dy: style.lineWidth / 2))
        let start = style.startAngle * .pi / 180
        arc.transform = CATransform3DMakeRotation(start, 0, 0, 1)
        arc.removeAnimation(forKey: Self.spinKey)
        guard animate else { return }
        let spin = loop("transform.rotation.z", from: start, to: start + 2 * .pi, duration: style.duration)
        spin.beginTime = beginTime(for: arc)
        arc.add(spin, forKey: Self.spinKey)
    }
}

struct ArcSpinner: NSViewRepresentable {
    var style: ArcSpinnerView.Style
    var animated: Bool = true

    func makeNSView(context: Context) -> ArcSpinnerView {
        let v = ArcSpinnerView(style: style)
        v.animated = animated
        return v
    }

    func updateNSView(_ v: ArcSpinnerView, context: Context) {
        v.style = style
        v.animated = animated
    }
}

// MARK: - Arc ring loader

/// `.arc-ring`: a thin cyan ring with a glow, a spinning quarter-arc
/// highlight, and a pulsing core.
final class ArcRingView: LayerAnimationView {
    static let spinKey = "aerie.arcring.spin"
    static let pulseScaleKey = "aerie.arcring.scale"
    static let pulseOpacityKey = "aerie.arcring.opacity"

    let ring = CAShapeLayer()
    let highlight = CAShapeLayer()
    let core = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.masksToBounds = false
        for shape in [ring, highlight] {
            shape.fillColor = nil
            shape.lineWidth = 1
            shape.shadowOffset = .zero
        }
        ring.strokeColor = NSColor(AerieColor.arcLine).cgColor
        ring.shadowColor = NSColor(AerieColor.arcGlow).cgColor
        ring.shadowOpacity = 1
        ring.shadowRadius = 5
        highlight.strokeColor = NSColor(AerieColor.arc).cgColor
        highlight.strokeEnd = 0.25
        core.backgroundColor = NSColor(AerieColor.arc).cgColor
        core.shadowColor = NSColor(AerieColor.arcGlow).cgColor
        core.shadowOpacity = 1
        core.shadowRadius = 6
        core.shadowOffset = .zero
        layer?.addSublayer(ring)
        layer?.addSublayer(highlight)
        layer?.addSublayer(core)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func rebuild(size: CGSize, animate: Bool) {
        let rect = CGRect(origin: .zero, size: size)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        for shape in [ring, highlight] {
            shape.bounds = rect
            shape.position = centre
            shape.path = circlePath(in: rect.insetBy(dx: 0.5, dy: 0.5))
        }
        let coreSize = max(size.width - 16, 2)
        core.bounds = CGRect(x: 0, y: 0, width: coreSize, height: coreSize)
        core.position = centre
        core.cornerRadius = coreSize / 2

        highlight.removeAnimation(forKey: Self.spinKey)
        core.removeAnimation(forKey: Self.pulseScaleKey)
        core.removeAnimation(forKey: Self.pulseOpacityKey)
        guard animate else { return }
        let spin = loop("transform.rotation.z", from: 0, to: 2 * CGFloat.pi, duration: 1.1)
        spin.beginTime = beginTime(for: highlight)
        highlight.add(spin, forKey: Self.spinKey)
        let scale = loop("transform.scale", from: 1, to: 0.82, duration: 0.8, autoreverses: true, ease: true)
        let opacity = loop("opacity", from: 1, to: 0.55, duration: 0.8, autoreverses: true, ease: true)
        scale.beginTime = beginTime(for: core)
        opacity.beginTime = beginTime(for: core)
        core.add(scale, forKey: Self.pulseScaleKey)
        core.add(opacity, forKey: Self.pulseOpacityKey)
    }
}

struct ArcRingLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> ArcRingView {
        let v = ArcRingView()
        v.animated = true
        return v
    }
    func updateNSView(_ v: ArcRingView, context: Context) {}
}

// MARK: - Progress sweep

/// `.progress-track`: a hairline with a glowing band sweeping left → right.
final class ProgressSweepView: LayerAnimationView {
    static let sweepKey = "aerie.sweep.position"

    var color: Color {
        didSet { if color != oldValue { applyColor(); invalidateLayers() } }
    }
    private let track = CALayer()
    let band = CAGradientLayer()

    init(color: Color) {
        self.color = color
        super.init(frame: .zero)
        track.backgroundColor = NSColor(AerieColor.glassLine).cgColor
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.shadowOpacity = 1
        band.shadowRadius = 6
        band.shadowOffset = .zero
        layer?.addSublayer(track)
        layer?.addSublayer(band)
        applyColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyColor() {
        let c = NSColor(color)
        band.colors = [NSColor.clear.cgColor, c.cgColor, NSColor.clear.cgColor]
        band.shadowColor = c.withAlphaComponent(0.7).cgColor
    }

    /// Band centre at the start and end of one sweep: the band (a quarter of
    /// the width) travels from fully off the left edge to fully off the right.
    static func sweep(width w: CGFloat, height h: CGFloat) -> (bounds: CGRect, from: CGPoint, to: CGPoint) {
        let bw = w * 0.25
        return (CGRect(x: 0, y: 0, width: bw, height: h),
                CGPoint(x: -w + bw / 2, y: h / 2),
                CGPoint(x: w + bw / 2, y: h / 2))
    }

    override func rebuild(size: CGSize, animate: Bool) {
        track.frame = CGRect(origin: .zero, size: size)
        let s = Self.sweep(width: size.width, height: size.height)
        band.bounds = s.bounds
        band.position = s.from
        band.removeAnimation(forKey: Self.sweepKey)
        guard animate else { return }
        let move = loop("position", from: s.from, to: s.to, duration: 1.1, ease: true)
        move.beginTime = beginTime(for: band)
        band.add(move, forKey: Self.sweepKey)
    }
}

struct ProgressSweepLayer: NSViewRepresentable {
    var color: Color
    func makeNSView(context: Context) -> ProgressSweepView {
        let v = ProgressSweepView(color: color)
        v.animated = true
        return v
    }
    func updateNSView(_ v: ProgressSweepView, context: Context) { v.color = color }
}

// MARK: - Console caret

/// `.caret`: a 7×12 arc block that blinks on/off every half second with a
/// glow. Discrete keyframes reproduce CSS `steps(2)`.
final class ConsoleCaretView: LayerAnimationView {
    static let blinkKey = "aerie.caret.blink"
    let block = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.masksToBounds = false
        block.backgroundColor = NSColor(AerieColor.arc).cgColor
        block.shadowColor = NSColor(AerieColor.arcGlow).cgColor
        block.shadowOpacity = 1
        block.shadowRadius = 4
        block.shadowOffset = .zero
        layer?.addSublayer(block)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func rebuild(size: CGSize, animate: Bool) {
        block.frame = CGRect(origin: .zero, size: size)
        block.removeAnimation(forKey: Self.blinkKey)
        guard animate else { return }
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0]
        blink.keyTimes = [0, 0.5]
        blink.calculationMode = .discrete
        blink.duration = 1
        blink.repeatCount = .infinity
        blink.beginTime = beginTime(for: block)
        block.add(blink, forKey: Self.blinkKey)
    }
}

struct ConsoleCaretLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> ConsoleCaretView {
        let v = ConsoleCaretView()
        v.animated = true
        return v
    }
    func updateNSView(_ v: ConsoleCaretView, context: Context) {}
}
