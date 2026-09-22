import SwiftUI

/// The Settings sidebar icons, translated 1:1 from the v2 design's inline SVGs
/// (`settings.jsx`). Each is drawn in the design's 16×16 viewBox and scaled to
/// the requested point size, stroked at the design's 1.4 px weight with round
/// caps/joins — matching the thin-line house style rather than SF Symbols.
struct SidebarIcon: View {
    enum Kind { case key, folder, cpu, spark, appearance, sliders, info }

    let kind: Kind
    var size: CGFloat = 14
    var color: Color

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 16
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            var stroke = Path()
            switch kind {
            case .key:
                stroke.addEllipse(in: CGRect(x: 2 * s, y: 8 * s, width: 6 * s, height: 6 * s))
                stroke.move(to: P(7, 9));  stroke.addLine(to: P(13.5, 2.5))
                stroke.move(to: P(11, 5)); stroke.addLine(to: P(13, 7))

            case .folder:
                stroke.move(to: P(2, 4.5))
                stroke.addQuadCurve(to: P(3, 3.5), control: P(2, 3.5))
                stroke.addLine(to: P(6, 3.5))
                stroke.addLine(to: P(7.5, 5))
                stroke.addLine(to: P(13, 5))
                stroke.addQuadCurve(to: P(14, 6), control: P(14, 5))
                stroke.addLine(to: P(14, 12))
                stroke.addQuadCurve(to: P(13, 13), control: P(14, 13))
                stroke.addLine(to: P(3, 13))
                stroke.addQuadCurve(to: P(2, 12), control: P(2, 13))
                stroke.closeSubpath()

            case .cpu:
                // A small chip: square body + 4 pins per side, matching the
                // thin-line house style of the other glyphs.
                stroke.addRect(CGRect(x: 5 * s, y: 5 * s, width: 6 * s, height: 6 * s))
                stroke.move(to: P(6, 5));  stroke.addLine(to: P(6, 3))
                stroke.move(to: P(8, 5));  stroke.addLine(to: P(8, 3))
                stroke.move(to: P(10, 5)); stroke.addLine(to: P(10, 3))
                stroke.move(to: P(6, 11));  stroke.addLine(to: P(6, 13))
                stroke.move(to: P(8, 11));  stroke.addLine(to: P(8, 13))
                stroke.move(to: P(10, 11)); stroke.addLine(to: P(10, 13))
                stroke.move(to: P(5, 6));  stroke.addLine(to: P(3, 6))
                stroke.move(to: P(5, 10)); stroke.addLine(to: P(3, 10))
                stroke.move(to: P(11, 6));  stroke.addLine(to: P(13, 6))
                stroke.move(to: P(11, 10)); stroke.addLine(to: P(13, 10))

            case .spark:
                break   // filled, drawn below

            case .appearance:
                // "Aa" — a large and a small letter A, the standard
                // text-size glyph (design `settings.jsx` AppearanceIcon).
                stroke.move(to: P(2.5, 13)); stroke.addLine(to: P(6, 3)); stroke.addLine(to: P(9.5, 13))
                stroke.move(to: P(3.4, 10)); stroke.addLine(to: P(8.6, 10))
                stroke.move(to: P(11, 13));  stroke.addLine(to: P(13, 7)); stroke.addLine(to: P(15, 13))
                stroke.move(to: P(11.5, 11)); stroke.addLine(to: P(14.5, 11))

            case .sliders:
                stroke.move(to: P(2, 4));  stroke.addLine(to: P(9, 4))
                stroke.move(to: P(11, 4)); stroke.addLine(to: P(14, 4))
                stroke.move(to: P(2, 12)); stroke.addLine(to: P(5, 12))
                stroke.move(to: P(7, 12)); stroke.addLine(to: P(14, 12))
                stroke.addEllipse(in: CGRect(x: 8.5 * s, y: 2.5 * s, width: 3 * s, height: 3 * s))
                stroke.addEllipse(in: CGRect(x: 4.5 * s, y: 10.5 * s, width: 3 * s, height: 3 * s))

            case .info:
                stroke.addEllipse(in: CGRect(x: 2 * s, y: 2 * s, width: 12 * s, height: 12 * s))
                stroke.move(to: P(8, 7.2)); stroke.addLine(to: P(8, 11.2))
            }

            ctx.stroke(
                stroke,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round, lineJoin: .round)
            )

            // The AI Review spark (`settings.jsx` SparkIcon) is filled: a
            // four-point star plus a smaller one at 70% opacity.
            if kind == .spark {
                func star(_ pts: [(CGFloat, CGFloat)]) -> Path {
                    var p = Path()
                    p.move(to: P(pts[0].0, pts[0].1))
                    for pt in pts.dropFirst() { p.addLine(to: P(pt.0, pt.1)) }
                    p.closeSubpath()
                    return p
                }
                ctx.fill(star([(8, 1.5), (9.15, 4.85), (12.5, 6), (9.15, 7.15), (8, 10.5), (6.85, 7.15), (3.5, 6), (6.85, 4.85)]),
                         with: .color(color))
                ctx.fill(star([(12.4, 10.2), (12.9, 11.6), (14.3, 12.1), (12.9, 12.6), (12.4, 14), (11.9, 12.6), (10.5, 12.1), (11.9, 11.6)]),
                         with: .color(color.opacity(0.7)))
            }

            // The info "i" dot is filled, not stroked.
            if kind == .info {
                let r: CGFloat = 0.85 * s
                let dot = Path(ellipseIn: CGRect(x: 8 * s - r, y: 5 * s - r, width: 2 * r, height: 2 * r))
                ctx.fill(dot, with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}
