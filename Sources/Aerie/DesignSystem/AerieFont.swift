import SwiftUI

enum AerieFont {
    static let sans = "Inter"            // installed via the .app bundle (see Task 1.6)
    static let mono = "JetBrains Mono"

    /// The two bundled families, for the `custom(_:size:)` escape hatch used by
    /// the few call sites that need an arbitrary one-off size.
    enum Family {
        case sans, mono
        var name: String { self == .sans ? AerieFont.sans : AerieFont.mono }
    }

    /// A resolved-on-demand text style. Carries the *base* size (the value at
    /// 100%); `resolve(scale:)` multiplies it by the live interface font scale.
    /// Apply with `.aerieFont(_:)`, never `.font(_:)`, so text rescales when the
    /// Settings → Appearance control changes `\.interfaceFontScale`.
    struct Style {
        let family: String
        let size: CGFloat
        var weight: Font.Weight = .regular
        var usesMonospacedDigit: Bool = false

        func weight(_ w: Font.Weight) -> Style {
            var c = self; c.weight = w; return c
        }

        func monospacedDigit() -> Style {
            var c = self; c.usesMonospacedDigit = true; return c
        }

        func resolve(scale: CGFloat) -> Font {
            var font = Font.custom(family, size: size * scale).weight(weight)
            if usesMonospacedDigit { font = font.monospacedDigit() }
            return font
        }
    }

    /// Escape hatch for one-off inline sizes (`.aerieFont(AerieFont.custom(.sans, size: 14.5))`).
    static func custom(_ family: Family, size: CGFloat) -> Style {
        Style(family: family.name, size: size)
    }

    // Common sizes. Interface zoom is applied per-font via `.aerieFont(_:)` —
    // NOT geometrically (a root `scaleEffect` rasterises and blurs text) and NOT
    // via Dynamic Type (macOS SwiftUI ignores `\.dynamicTypeSize` for fonts).
    static func display() -> Style  { Style(family: sans, size: 30, weight: .light) }
    /// Main-window page heading (`.section-title`): 26pt medium.
    static func pageTitle() -> Style { Style(family: sans, size: 26, weight: .medium) }
    static func sectionTitle() -> Style  { Style(family: sans, size: 22, weight: .medium) }
    static func body() -> Style      { Style(family: sans, size: 13.5) }
    static func small() -> Style     { Style(family: sans, size: 12) }
    static func eyebrow() -> Style   { Style(family: mono, size: 10, weight: .medium) }
    static func code(_ size: CGFloat = 12) -> Style { Style(family: mono, size: size) }
}

// MARK: - Interface font scale (environment-driven, app-wide)

private struct InterfaceFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// Live interface font scale (1.0 = 100%). Published at the window roots by
    /// `AerieApp.InterfaceZoom` from the shared `AppearanceViewModel`.
    var interfaceFontScale: CGFloat {
        get { self[InterfaceFontScaleKey.self] }
        set { self[InterfaceFontScaleKey.self] = newValue }
    }
}

extension View {
    /// Applies an `AerieFont.Style`, scaled by the live `\.interfaceFontScale`.
    /// Use everywhere instead of `.font(AerieFont.…)`: because the modifier
    /// reads the environment, every text view re-renders at the new size when
    /// the scale changes — no rebuild, no lost state, crisp at any size.
    func aerieFont(_ style: AerieFont.Style) -> some View {
        modifier(AerieFontScaleModifier(style: style))
    }
}

private struct AerieFontScaleModifier: ViewModifier {
    let style: AerieFont.Style
    @Environment(\.interfaceFontScale) private var scale

    func body(content: Content) -> some View {
        content.font(style.resolve(scale: scale))
    }
}
