import SwiftUI

/// A monospace branch-name tag with a small branch glyph.
///
/// Visual contract: `docs/superpowers/design/v2/screens.jsx` `BranchTag(...)`.
/// Amber-tinted when `isCurrent == true` so the user can spot the checked-out
/// branch at a glance.
struct BranchTag: View {
    let name: String
    var isCurrent: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            BranchGlyph()
                .frame(width: 11, height: 11)
                .foregroundStyle(foreground.opacity(0.7))
            Text(name)
                .font(AerieFont.code(11.5))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
    }

    private var foreground: Color {
        isCurrent ? AerieColor.amber : AerieColor.text1
    }

    private var background: Color {
        isCurrent ? AerieColor.amberSoft : AerieColor.glass2
    }

    private var border: Color {
        isCurrent ? AerieColor.amberLine : AerieColor.glassLine
    }
}

/// Small branch icon: two stacked nodes connected to a side node, mirroring
/// the SVG used in the design source (`BranchTiny`). Module-internal so the
/// Settings → Repositories rows can reuse the same glyph.
struct BranchGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            // Coordinates scaled from a 16×16 design.
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x / 16 * s, y: y / 16 * s)
            }
            // Vertical trunk
            var trunk = Path()
            trunk.move(to: p(4, 4.4))
            trunk.addLine(to: p(4, 11.6))
            ctx.stroke(trunk, with: .color(.primary), style: stroke)

            // Branch off
            var arc = Path()
            arc.move(to: p(4, 8))
            arc.addCurve(
                to: p(11, 5.4),
                control1: p(7, 8),
                control2: p(11, 7)
            )
            ctx.stroke(arc, with: .color(.primary), style: stroke)

            // Node dots
            for (cx, cy) in [(4.0, 3.0), (4.0, 13.0), (12.0, 6.0)] {
                let r: CGFloat = 1.4 / 16 * s
                let rect = CGRect(
                    x: cx / 16 * s - r,
                    y: cy / 16 * s - r,
                    width: r * 2,
                    height: r * 2
                )
                ctx.fill(Path(ellipseIn: rect), with: .color(.primary))
            }
        }
    }
}
