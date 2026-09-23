import XCTest
import AppKit
import QuartzCore
@testable import Aerie

/// The backdrop is a still scene on cached Core Animation layers: built once
/// per size, never animated, never re-rasterised with the SwiftUI tree.
@MainActor
final class BackdropLayerTests: XCTestCase {
    // MARK: - Geometry

    func test_nebulaGeometry_centreIsTwiceGradientMinusBackground() {
        let n = BackdropGeometry.nebula(
            gradientAt: CGPoint(x: 0.82, y: 0.08), radii: CGSize(width: 0.52, height: 0.44),
            bgAt: CGPoint(x: 0.42, y: 0.44), in: CGSize(width: 1000, height: 500))
        XCTAssertEqual(n.centre.x, (2 * 0.82 - 0.42) * 1000, accuracy: 0.001)
        XCTAssertEqual(n.centre.y, (2 * 0.08 - 0.44) * 500, accuracy: 0.001)
        XCTAssertEqual(n.size.width, 0.52 * 2 * 1000 * 2, accuracy: 0.001)
        XCTAssertEqual(n.size.height, 0.44 * 2 * 500 * 2, accuracy: 0.001)
    }

    func test_starGrid_coversTheViewWithWholeTiles() {
        let g = BackdropGeometry.starGrid(tile: 100, in: CGSize(width: 950, height: 420))
        XCTAssertEqual(g.columns, 10) // ceil(950 / 100)
        XCTAssertEqual(g.rows, 5)     // ceil(420 / 100)
    }

    // MARK: - Layers

    private func host(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.layoutSubtreeIfNeeded()
        return window
    }

    func test_starfield_tilesEveryDotGroupAndStaysStill() {
        let view = StarfieldView()
        let window = host(view)
        defer { window.close() }

        let groups = view.dotGroupLayers
        XCTAssertEqual(groups.count, StarfieldView.near.count + StarfieldView.far.count)
        for group in groups {
            XCTAssertEqual(group.bounds.size, CGSize(width: 800, height: 600))
            XCTAssertNil(group.animationKeys())
        }
        XCTAssertNil(view.nearLayer.animationKeys())
    }

    func test_nebulaField_placesEachCloudAndStaysStill() {
        let view = NebulaFieldView()
        let window = host(view)
        defer { window.close() }

        XCTAssertEqual(view.cloudLayers.count, NebulaFieldView.clouds.count)
        for (layer, cloud) in zip(view.cloudLayers, NebulaFieldView.clouds) {
            let geo = BackdropGeometry.nebula(
                gradientAt: cloud.gradientAt, radii: cloud.radii, bgAt: cloud.bgAt,
                in: CGSize(width: 800, height: 600))
            XCTAssertEqual(layer.position, geo.centre)
            XCTAssertEqual(layer.bounds.size, geo.size)
            XCTAssertNil(layer.animationKeys())
        }
    }

    func test_planetField_paintsAndPlacesEachPlanetAndStaysStill() {
        let view = PlanetFieldView()
        let window = host(view)
        defer { window.close() }

        XCTAssertEqual(view.planetLayers.count, PlanetFieldView.planets.count)
        for (layer, planet) in zip(view.planetLayers, PlanetFieldView.planets) {
            XCTAssertNotNil(layer.contents, "each planet is painted into a bitmap")
            XCTAssertEqual(layer.position, CGPoint(x: planet.centre.x * 800, y: planet.centre.y * 600))
            let diameter = (planet.diameter * 600).rounded()
            XCTAssertEqual(layer.bounds.width, diameter * PlanetArt.canvasRatio(planet.kind), accuracy: 0.001)
            XCTAssertNil(layer.animationKeys())
        }
    }

    func test_planetArt_paintsEveryKind() {
        for kind in PlanetArt.Kind.allCases {
            let image = PlanetArt.image(kind, diameter: 40, scale: 2)
            XCTAssertEqual(image?.width, Int((40 * PlanetArt.canvasRatio(kind) * 2).rounded(.up)))
        }
    }
}
