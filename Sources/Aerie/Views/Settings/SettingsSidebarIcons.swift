import SwiftUI

/// The Settings sidebar icons, translated 1:1 from the v2 design's inline SVGs
/// (`settings.jsx`). Each is drawn in the design's 16×16 viewBox and scaled to
/// the requested point size, stroked at the design's 1.4 px weight with round
/// caps/joins — matching the thin-line house style rather than SF Symbols.
struct SidebarIcon: View {
    enum Kind { case key, folder, pullRequest, plug, appearance, sliders, info }

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

            case .pullRequest:
                // Git pull-request glyph: left rail (top commit → base commit),
                // right rail branching off the top commit into the merge commit.
                stroke.addEllipse(in: CGRect(x: 2.5 * s, y: 2.5 * s, width: 3.5 * s, height: 3.5 * s))
                stroke.move(to: P(4.25, 6)); stroke.addLine(to: P(4.25, 10))
                stroke.addEllipse(in: CGRect(x: 2.5 * s, y: 10 * s, width: 3.5 * s, height: 3.5 * s))
                stroke.move(to: P(6, 4.25)); stroke.addLine(to: P(9, 4.25))
                stroke.addQuadCurve(to: P(11.75, 7), control: P(11.75, 4.25))
                stroke.addLine(to: P(11.75, 10))
                stroke.addEllipse(in: CGRect(x: 10 * s, y: 10 * s, width: 3.5 * s, height: 3.5 * s))

            case .plug:
                stroke.move(to: P(5, 2));  stroke.addLine(to: P(5, 5))
                stroke.move(to: P(11, 2)); stroke.addLine(to: P(11, 5))
                stroke.move(to: P(3.5, 5))
                stroke.addLine(to: P(12.5, 5))
                stroke.addLine(to: P(12.5, 8))
                stroke.addArc(center: P(8, 8), radius: 4.5 * s,
                              startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                stroke.addLine(to: P(3.5, 5))
                stroke.move(to: P(8, 12.5)); stroke.addLine(to: P(8, 15))

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
