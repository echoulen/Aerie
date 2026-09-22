import SwiftUI

// MARK III geometry — chamfered plates instead of rounded rectangles.
// Design source: `src/v2/styles.css` (`.card`, `.btn`, `--hull`).

/// A card plate: top-right and bottom-left corners clipped at 45°
/// (`.card` clip-path, 16px cut).
struct HudPlateShape: InsettableShape {
    var cut: CGFloat = 16
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = max(0, min(cut - inset * 0.6, min(r.width, r.height) / 2))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> HudPlateShape {
        var s = self; s.inset += amount; return s
    }
}

/// A bevelled HUD key: top-left and bottom-right corners clipped
/// (`.btn` clip-path, `--cut` 9px; 6px for `.sm`).
struct HudKeyShape: InsettableShape {
    var cut: CGFloat = 9
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = max(0, min(cut - inset * 0.6, min(r.width, r.height) / 2))
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> HudKeyShape {
        var s = self; s.inset += amount; return s
    }
}

/// The window hull — an asymmetric chassis outline (`--hull`): bevel top-left,
/// notched step top-right, clipped bottom-right, small nick bottom-left.
///
/// The window lights sit inset in the titlebar past the top-left bevel
/// (`topLeftCut`); see `TrafficLights`.
struct HullShape: InsettableShape {
    var topLeftCut: CGFloat = 40
    var notchInset: CGFloat = 132   // distance of the notch from the right edge
    var notchDepth: CGFloat = 16
    var bottomRightCut: CGFloat = 26
    var bottomLeftCut: CGFloat = 22
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let tl = max(0, topLeftCut - inset * 0.6)
        let br = max(0, bottomRightCut - inset * 0.6)
        let bl = max(0, bottomLeftCut - inset * 0.6)
        let step = notchDepth + inset * 0.4
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addLine(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - notchInset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - notchInset + notchDepth + 2, y: r.minY + step))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + step))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addLine(to: CGPoint(x: r.maxX - br, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - bl))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> HullShape {
        var s = self; s.inset += amount; return s
    }
}

// MARK: - Ornaments

/// `.hud-corners` — two L-shaped gold brackets (top-left + bottom-right).
struct HudCorners: View {
    var length: CGFloat = 14
    var color: Color = AerieColor.amberLine

    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                p.move(to: CGPoint(x: 0, y: length)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: length, y: 0))
                p.move(to: CGPoint(x: w - length, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - length))
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// `.hud-note` — a mono telemetry label led by a fading hairline tick.
struct HudNote: View {
    let text: String
    /// Let the label shrink and truncate (middle) instead of always taking its
    /// full width — for notes carrying user data such as a branch name, which
    /// would otherwise push a narrow layout wider than the window.
    var truncates: Bool = false
    var color: Color = AerieColor.text3

    var body: some View {
        HStack(spacing: 8) {
            LinearGradient(colors: [.clear, AerieColor.amberLine], startPoint: .leading, endPoint: .trailing)
                .frame(width: 18, height: 1)
            Text(text.uppercased())
                .aerieFont(AerieFont.code(10))
                .tracking(1.8)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .fixedSize(horizontal: !truncates, vertical: true)
    }
}

/// `.hud-rail` — a measured ruler edge of 1px ticks every 12pt.
struct HudRail: View {
    var spacing: CGFloat = 12
    var height: CGFloat = 6
    var color: Color = AerieColor.glassLine2

    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(color))
                x += spacing
            }
        }
        .frame(height: height)
        .opacity(0.7)
        .allowsHitTesting(false)
    }
}

/// `.section-eyebrow` — gold mono overline used above page titles.
struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .aerieFont(AerieFont.eyebrow())
            .tracking(2.6)                    // 0.26em @ 10pt
            .foregroundStyle(AerieColor.amber.opacity(0.72))
    }
}

// MARK: - Energy / progress

/// `.arc-ring` — the arc-reactor loader used by running states: a thin cyan
/// ring with a spinning highlight arc and a pulsing core. Core Animation
/// (`ArcRingView`); the SwiftUI shell only sizes it.
struct ArcRing: View {
    var size: CGFloat = 26

    var body: some View {
        ArcRingLayer().frame(width: size, height: size)
    }
}

/// `.progress-track` — a 2pt hairline with a glowing sweep running across it.
/// Core Animation (`ProgressSweepView`).
struct ProgressSweep: View {
    enum Tone { case amber, arc, danger }
    var tone: Tone = .amber

    private var color: Color {
        switch tone {
        case .amber:  return AerieColor.amber
        case .arc:    return AerieColor.arc
        case .danger: return AerieColor.crimsonHot
        }
    }

    var body: some View {
        ProgressSweepLayer(color: color).frame(height: 2)
    }
}

// MARK: - Buttons

/// The MARK III bevelled button (`.btn` and its variants).
///
///     Button("Merge") { … }.buttonStyle(.hud(.amber, size: .small))
struct HudButtonStyle: ButtonStyle {
    enum Kind { case standard, ghost, amber, arc, danger }
    enum Size { case regular, small }

    var kind: Kind = .standard
    var size: Size = .regular
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HudButtonBody(configuration: configuration, kind: kind, size: size, isEnabled: isEnabled)
    }
}

private struct HudButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: HudButtonStyle.Kind
    let size: HudButtonStyle.Size
    let isEnabled: Bool
    @State private var hovering = false

    private var cut: CGFloat { size == .small ? 6 : 9 }
    private var shape: HudKeyShape { HudKeyShape(cut: cut) }

    var body: some View {
        configuration.label
            .aerieFont(font)
            .tracking(kind == .amber ? 1.0 : 0.75)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .small ? 11 : 15)
            .padding(.vertical, size == .small ? 5 : 8)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(stroke, lineWidth: 1))
            .overlay(alignment: .top) {
                if kind == .amber || kind == .standard {
                    shape.strokeBorder(Color.white.opacity(kind == .amber ? 0.40 : 0.08), lineWidth: 1)
                        .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                }
            }
            .shadow(color: glow, radius: glow == .clear ? 0 : 9)
            .brightness(kind == .amber && hovering ? 0.04 : 0)
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
            .onHover { hovering = $0 && isEnabled }
            .animation(.easeOut(duration: 0.18), value: hovering)
    }

    private var font: AerieFont.Style {
        let base = AerieFont.custom(.sans, size: size == .small ? 11.5 : 12.5)
        return kind == .amber ? base.weight(.bold) : base.weight(.medium)
    }

    private var foreground: Color {
        switch kind {
        case .standard: return AerieColor.text1
        case .ghost:    return hovering ? AerieColor.text1 : AerieColor.text3
        case .amber:    return AerieColor.amberInk
        case .arc:      return AerieColor.arc
        case .danger:   return AerieColor.crimsonHot
        }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .standard: return AnyShapeStyle(hovering ? AerieColor.glass3 : AerieColor.glass2)
        case .ghost:    return AnyShapeStyle(hovering ? AerieColor.glass2 : Color.clear)
        case .amber:
            return AnyShapeStyle(LinearGradient(colors: [AerieColor.amberFillTop, AerieColor.amberFillBot],
                                                startPoint: .top, endPoint: .bottom))
        case .arc:      return AnyShapeStyle(AerieColor.arc.opacity(hovering ? 0.22 : 0.13))
        case .danger:   return AnyShapeStyle(hovering ? AerieColor.dangerFillHover : AerieColor.crimsonSoft)
        }
    }

    private var stroke: Color {
        switch kind {
        case .standard: return hovering ? AerieColor.amberLine : AerieColor.glassLine2
        case .ghost:    return hovering ? AerieColor.glassLine : .clear
        case .amber:    return AerieColor.amberCtaLine
        case .arc:      return hovering ? AerieColor.arc : AerieColor.arcLine
        case .danger:   return hovering ? AerieColor.crimsonHot : AerieColor.crimsonLine
        }
    }

    private var glow: Color {
        guard isEnabled else { return .clear }
        switch kind {
        case .standard: return hovering ? AerieColor.amberGlow.opacity(0.35) : .clear
        case .ghost:    return .clear
        case .amber:    return AerieColor.amberGlow.opacity(hovering ? 0.55 : 0.40)
        case .arc:      return AerieColor.arcGlow.opacity(0.30)
        case .danger:   return hovering ? AerieColor.crimson.opacity(0.45) : .clear
        }
    }
}

extension ButtonStyle where Self == HudButtonStyle {
    static func hud(_ kind: HudButtonStyle.Kind = .standard, size: HudButtonStyle.Size = .regular) -> HudButtonStyle {
        HudButtonStyle(kind: kind, size: size)
    }
}
