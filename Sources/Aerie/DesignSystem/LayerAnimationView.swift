import AppKit
import QuartzCore

/// Shared base for the HUD's Core Animation–driven views (backdrop, brand
/// mark, live dots, spinners). SwiftUI's `repeatForever` re-renders the view
/// every frame on the main thread; here content is built once on CALayers and
/// the motion is a render-server animation.
///
/// What the base provides:
/// - top-left origin (`isFlipped`) so layer maths reads like SwiftUI's;
/// - a shared epoch for `beginTime`, so rebuilding on resize keeps every
///   animation in phase instead of restarting it;
/// - a rebuild hook that runs when the size or `animated` changes;
/// - **occlusion freeze**: when the hosting window is fully covered, minimised
///   or on another Space, the root layer's clock stops (QA1673: `speed = 0`
///   plus `timeOffset`), so a monitor app parked behind other windows costs
///   the render server nothing. Resuming clears the offset, which snaps back
///   to the absolute-time phase — the jump lands while the window is still
///   unseen;
/// - no hit-testing, so overlaying one never eats a click.
class LayerAnimationView: NSView {
    var animated = false {
        didSet { if animated != oldValue { invalidateLayers() } }
    }

    /// True while the root clock is stopped (window not visible). Exposed for
    /// tests; production callers never set it directly.
    private(set) var isFrozen = false

    private let epoch = CACurrentMediaTime()
    private var lastSize: CGSize?
    private var occlusionToken: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.masksToBounds = true
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let occlusionToken { NotificationCenter.default.removeObserver(occlusionToken) }
    }

    /// Top-left origin, matching SwiftUI. AppKit manages a hosted layer's
    /// `isGeometryFlipped` from this, so setting it on the layer directly
    /// doesn't stick.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeOcclusion()
        applyContentsScale()
        invalidateLayers()
        applyVisibility()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyContentsScale()
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 0, size.height > 0, size != lastSize else { return }
        lastSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuild(size: size, animate: animated && window != nil)
        applyContentsScale()
        CATransaction.commit()
    }

    /// Lay the layers out for `size` and attach or strip animations.
    func rebuild(size: CGSize, animate: Bool) {}

    /// Forces `rebuild` on the next layout pass — for style changes that
    /// don't move the view.
    func invalidateLayers() {
        lastSize = nil
        needsLayout = true
    }

    func beginTime(for layer: CALayer) -> CFTimeInterval {
        layer.convertTime(epoch, from: nil)
    }

    /// Stops or restarts the root layer's clock. Freezing records the current
    /// local time in `timeOffset`; plain `speed = 0` would pin local time at
    /// zero, which is before every `beginTime`, and CA would show the
    /// un-animated model values instead of the current frame.
    func setFrozen(_ freeze: Bool) {
        guard let root = layer, freeze != isFrozen else { return }
        isFrozen = freeze
        if freeze {
            let now = root.convertTime(CACurrentMediaTime(), from: nil)
            root.speed = 0
            root.timeOffset = now
        } else {
            root.speed = 1
            root.timeOffset = 0
        }
    }

    // MARK: Internals

    private func observeOcclusion() {
        if let occlusionToken { NotificationCenter.default.removeObserver(occlusionToken) }
        occlusionToken = nil
        guard let window else { return }
        occlusionToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in self?.applyVisibility() }
    }

    private func applyVisibility() {
        // No window yet → nothing is drawing anyway; leave the clock running so
        // the first frame after attach is live.
        guard let window else { return setFrozen(false) }
        setFrozen(!window.occlusionState.contains(.visible))
    }

    private func applyContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        func apply(_ l: CALayer) {
            l.contentsScale = scale
            l.sublayers?.forEach(apply)
        }
        if let layer { apply(layer) }
    }
}
