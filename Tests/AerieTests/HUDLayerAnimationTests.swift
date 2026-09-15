import XCTest
import AppKit
import QuartzCore
import SwiftUI
@testable import Aerie

/// The HUD's small persistent animations run on Core Animation; each view must
/// attach its animations when animated, attach none otherwise, and the shared
/// base must freeze/resume the root clock for occluded windows.
@MainActor
final class HUDLayerAnimationTests: XCTestCase {
    private func host(_ view: NSView, size: CGSize = CGSize(width: 40, height: 40)) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        return window
    }

    // MARK: Freeze

    func test_setFrozen_stopsAndRestartsTheRootClock() {
        let view = ConsoleCaretView()
        let window = host(view)
        defer { window.close() }
        view.setFrozen(true)
        XCTAssertEqual(view.layer?.speed, 0)
        XCTAssertGreaterThan(view.layer?.timeOffset ?? 0, 0, "frozen at the current local time, not at 0")
        XCTAssertTrue(view.isFrozen)
        view.setFrozen(false)
        XCTAssertEqual(view.layer?.speed, 1)
        XCTAssertEqual(view.layer?.timeOffset, 0)
        XCTAssertFalse(view.isFrozen)
    }

    // MARK: Breathing dot

    func test_breathingDot_animatesOpacityAndScale_whenAnimated() {
        let view = BreathingDotView(style: .init(color: AerieColor.ok, glow: AerieColor.ok))
        view.animated = true
        let window = host(view, size: CGSize(width: 6, height: 6))
        defer { window.close() }
        let opacity = view.dot.animation(forKey: BreathingDotView.opacityKey) as? CABasicAnimation
        let scale = view.dot.animation(forKey: BreathingDotView.scaleKey) as? CABasicAnimation
        XCTAssertEqual(opacity?.keyPath, "opacity")
        XCTAssertEqual(opacity?.toValue as? Float, 0.55)
        XCTAssertEqual(opacity?.autoreverses, true)
        XCTAssertEqual(opacity?.duration, 0.9, "half a 1.8 s breath each way")
        XCTAssertEqual(scale?.keyPath, "transform.scale")
        XCTAssertEqual(view.dot.cornerRadius, 3)
        XCTAssertEqual(view.dot.shadowOpacity, 1)
    }

    func test_breathingDot_isStillAndUnglowed_whenPaused() {
        let view = BreathingDotView(style: .init(color: AerieColor.text4, glow: nil))
        view.animated = false
        let window = host(view, size: CGSize(width: 6, height: 6))
        defer { window.close() }
        XCTAssertNil(view.dot.animationKeys())
        XCTAssertEqual(view.dot.shadowOpacity, 0)
    }

    func test_breathingDot_styleChange_rebuilds() {
        let view = BreathingDotView(style: .init(color: AerieColor.ok, glow: AerieColor.ok))
        view.animated = true
        let window = host(view, size: CGSize(width: 6, height: 6))
        defer { window.close() }
        XCTAssertNotNil(view.dot.animation(forKey: BreathingDotView.opacityKey))
        view.animated = false
        view.style = .init(color: AerieColor.text4, glow: nil)
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(view.dot.animationKeys())
    }

    // MARK: Brand mark

    func test_brandMark_breathesItsGlowRadius() {
        let view = BrandMarkView()
        view.animated = true
        let window = host(view, size: CGSize(width: 14, height: 14))
        defer { window.close() }
        let glow = view.layer?.sublayers?.first
        let breathe = glow?.animation(forKey: BrandMarkView.glowKey) as? CABasicAnimation
        XCTAssertEqual(breathe?.keyPath, "shadowRadius")
        XCTAssertEqual(breathe?.fromValue as? CGFloat, 5)
        XCTAssertEqual(breathe?.toValue as? CGFloat, 10)
        XCTAssertEqual(breathe?.autoreverses, true)
    }

    func test_brandMark_holdsStill_whenNotPulsing() {
        let view = BrandMarkView()
        view.animated = false
        let window = host(view, size: CGSize(width: 14, height: 14))
        defer { window.close() }
        XCTAssertNil(view.layer?.sublayers?.first?.animationKeys())
    }

    // MARK: Spinner

    func test_arcSpinner_spinsFromItsStartAngle_withDashAndTrim() {
        let view = ArcSpinnerView(style: .init(
            color: AerieColor.arc, lineWidth: 2, trimTo: 0.5, startAngle: 45,
            duration: 0.7, shadow: AerieColor.arc, dash: [4, 6], diameter: 9))
        view.animated = true
        let window = host(view, size: CGSize(width: 11, height: 11))
        defer { window.close() }
        let spin = view.arc.animation(forKey: ArcSpinnerView.spinKey) as? CABasicAnimation
        XCTAssertEqual(spin?.keyPath, "transform.rotation.z")
        XCTAssertEqual(spin?.fromValue as? CGFloat ?? -1, 45 * .pi / 180, accuracy: 1e-6)
        XCTAssertEqual(spin?.duration, 0.7)
        XCTAssertEqual(view.arc.strokeEnd, 0.5)
        XCTAssertEqual(view.arc.lineDashPattern, [4, 6])
        XCTAssertEqual(view.arc.bounds.size, CGSize(width: 9, height: 9))
        XCTAssertEqual(view.arc.shadowOpacity, 1)
    }

    // MARK: Arc ring

    func test_arcRing_spinsHighlightAndPulsesCore() {
        let view = ArcRingView()
        view.animated = true
        let window = host(view, size: CGSize(width: 26, height: 26))
        defer { window.close() }
        XCTAssertNotNil(view.highlight.animation(forKey: ArcRingView.spinKey))
        XCTAssertNotNil(view.core.animation(forKey: ArcRingView.pulseScaleKey))
        XCTAssertNotNil(view.core.animation(forKey: ArcRingView.pulseOpacityKey))
        XCTAssertEqual(view.highlight.strokeEnd, 0.25)
        XCTAssertEqual(view.core.bounds.size, CGSize(width: 10, height: 10), "core is size − 16")
        XCTAssertNil(view.ring.animationKeys(), "the outer ring is static")
    }

    // MARK: Progress sweep

    func test_progressSweep_bandTravelsFullyAcross() {
        let s = ProgressSweepView.sweep(width: 400, height: 2)
        XCTAssertEqual(s.bounds.width, 100)
        XCTAssertEqual(s.from.x, -350, "starts fully off the left edge")
        XCTAssertEqual(s.to.x, 450, "ends fully off the right edge")

        let view = ProgressSweepView(color: AerieColor.amber)
        view.animated = true
        let window = host(view, size: CGSize(width: 400, height: 2))
        defer { window.close() }
        let move = view.band.animation(forKey: ProgressSweepView.sweepKey) as? CABasicAnimation
        XCTAssertEqual(move?.keyPath, "position")
        XCTAssertEqual(move?.fromValue as? CGPoint, s.from)
        XCTAssertEqual(move?.toValue as? CGPoint, s.to)
        XCTAssertEqual(move?.duration, 1.1)
        XCTAssertEqual(move?.autoreverses, false)
    }

    // MARK: Console caret

    func test_consoleCaret_blinksInDiscreteHalfSecondSteps() {
        let view = ConsoleCaretView()
        view.animated = true
        let window = host(view, size: CGSize(width: 7, height: 12))
        defer { window.close() }
        let blink = view.block.animation(forKey: ConsoleCaretView.blinkKey) as? CAKeyframeAnimation
        XCTAssertEqual(blink?.keyPath, "opacity")
        XCTAssertEqual(blink?.calculationMode, .discrete)
        XCTAssertEqual(blink?.duration, 1)
        XCTAssertEqual(blink?.keyTimes, [0, 0.5])
    }
}
