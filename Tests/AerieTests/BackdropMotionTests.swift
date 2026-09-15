import XCTest
import AppKit
import QuartzCore
@testable import Aerie

/// The backdrop's drift must run on Core Animation (a render-server animation
/// on a cached layer), not as a SwiftUI `repeatForever` that re-rasterises the
/// whole window every frame — that was pinning the main thread at ~40% CPU
/// while idle.
@MainActor
final class BackdropMotionTests: XCTestCase {
    // MARK: - Geometry

    func test_nebulaGeometry_centreIsTwiceGradientMinusBackground() {
        let n = BackdropGeometry.nebula(
            gradientAt: CGPoint(x: 0.82, y: 0.08), radii: CGSize(width: 0.52, height: 0.44),
            bgFrom: CGPoint(x: 0.42, y: 0.44), bgTo: CGPoint(x: 0.58, y: 0.56),
            in: CGSize(width: 1000, height: 500))
        XCTAssertEqual(n.from.x, (2 * 0.82 - 0.42) * 1000, accuracy: 0.001)
        XCTAssertEqual(n.from.y, (2 * 0.08 - 0.44) * 500, accuracy: 0.001)
        XCTAssertEqual(n.to.x, (2 * 0.82 - 0.58) * 1000, accuracy: 0.001)
        XCTAssertEqual(n.to.y, (2 * 0.08 - 0.56) * 500, accuracy: 0.001)
        XCTAssertEqual(n.size.width, 0.52 * 2 * 1000 * 2, accuracy: 0.001)
        XCTAssertEqual(n.size.height, 0.44 * 2 * 500 * 2, accuracy: 0.001)
    }

    func test_starGrid_upLeftTravelOversizesByOneLoopAndStartsAtOrigin() {
        let g = BackdropGeometry.starGrid(
            tile: 100, direction: CGSize(width: -2, height: -1), speed: 10,
            in: CGSize(width: 950, height: 420))
        XCTAssertEqual(g.layerSize, CGSize(width: 1150, height: 520))
        XCTAssertEqual(g.origin, .zero)
        XCTAssertEqual(g.travel, CGSize(width: -200, height: -100))
        XCTAssertEqual(g.columns, 12) // ceil(1150 / 100)
        XCTAssertEqual(g.rows, 6)     // ceil(520 / 100)
        XCTAssertEqual(g.duration, (200.0 * 200 + 100 * 100).squareRoot() / 10, accuracy: 0.0001)
    }

    func test_starGrid_downRightTravelStartsShiftedBack() {
        let g = BackdropGeometry.starGrid(
            tile: 50, direction: CGSize(width: 1, height: 2), speed: 5,
            in: CGSize(width: 300, height: 300))
        XCTAssertEqual(g.origin, CGPoint(x: -50, y: -100))
    }

    // MARK: - Core Animation wiring

    private func host(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.layoutSubtreeIfNeeded()
        return window
    }

    func test_starfield_driftsEveryDotGroupOnCoreAnimation() {
        let view = StarfieldView()
        view.animated = true
        let window = host(view)
        defer { window.close() }

        let groups = view.dotGroupLayers
        XCTAssertEqual(groups.count, StarfieldView.near.count + StarfieldView.far.count)
        for group in groups {
            let drift = group.animation(forKey: StarfieldView.driftKey) as? CABasicAnimation
            XCTAssertNotNil(drift, "each dot group drifts via a CA animation")
            XCTAssertEqual(drift?.keyPath, "position")
            XCTAssertEqual(drift?.repeatCount, .infinity)
            XCTAssertEqual(drift?.autoreverses, false)
        }
        XCTAssertNotNil(view.nearLayer.animation(forKey: StarfieldView.twinkleKey),
                        "the near layer twinkles via a CA opacity animation")
    }

    func test_starfield_staysStillWhenNotAnimated() {
        let view = StarfieldView()
        view.animated = false
        let window = host(view)
        defer { window.close() }

        XCTAssertFalse(view.dotGroupLayers.isEmpty)
        for group in view.dotGroupLayers {
            XCTAssertNil(group.animationKeys())
        }
        XCTAssertNil(view.nearLayer.animationKeys())
    }

    func test_nebulaField_swimsEachCloudBetweenItsKeyframes() {
        let view = NebulaFieldView()
        view.animated = true
        let window = host(view)
        defer { window.close() }

        XCTAssertEqual(view.cloudLayers.count, NebulaFieldView.clouds.count)
        for (layer, cloud) in zip(view.cloudLayers, NebulaFieldView.clouds) {
            let geo = BackdropGeometry.nebula(
                gradientAt: cloud.gradientAt, radii: cloud.radii,
                bgFrom: cloud.bgFrom, bgTo: cloud.bgTo, in: CGSize(width: 800, height: 600))
            let swim = layer.animation(forKey: NebulaFieldView.swimKey) as? CABasicAnimation
            XCTAssertEqual(swim?.keyPath, "position")
            XCTAssertEqual(swim?.fromValue as? CGPoint, geo.from)
            XCTAssertEqual(swim?.toValue as? CGPoint, geo.to)
            XCTAssertEqual(swim?.duration, NebulaFieldView.swimSeconds)
            XCTAssertEqual(swim?.autoreverses, true)
            XCTAssertEqual(swim?.repeatCount, .infinity)
            XCTAssertEqual(layer.bounds.size, geo.size)
        }
    }

    func test_nebulaField_staysStillWhenNotAnimated() {
        let view = NebulaFieldView()
        view.animated = false
        let window = host(view)
        defer { window.close() }

        XCTAssertFalse(view.cloudLayers.isEmpty)
        for layer in view.cloudLayers { XCTAssertNil(layer.animationKeys()) }
    }
}
