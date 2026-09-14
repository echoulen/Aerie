import SwiftUI

// MARK III building blocks shared by the Settings screens, composed from the
// design-system primitives so every page renders the same header, wells,
// keycaps and toggle.
// Design source: `src/v2/settings.jsx`, `advanced.jsx`, `appearance.jsx`,
// `mcp.jsx` + `styles.css` (`.section-eyebrow`, `.section-title`).

extension View {
    /// The Settings page gutter from the design: 34 top, 40 sides, 40 bottom.
    func settingsPagePadding() -> some View {
        self
            .padding(.top, 34)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
    }
}

/// A Settings page header — `.section-eyebrow`, then 6pt below a row with the
/// `.section-title` (27 semibold, gold/0.25 text-shadow) and a mono 13 text-3
/// subtitle sharing a baseline; trailing actions are bottom-aligned.
struct SettingsPageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var subtitleSize: CGFloat = 13
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(text: eyebrow)
            HStack(alignment: .bottom, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(title)
                        .aerieFont(AerieFont.pageTitle())
                        .tracking(0.13)                  // 0.005em @ 27pt
                        .foregroundStyle(AerieColor.text1)
                        .shadow(color: AerieColor.amber.opacity(0.25), radius: 15)
                        .lineLimit(1)
                        .fixedSize()
                    if let subtitle {
                        Text(subtitle)
                            .aerieFont(AerieFont.code(subtitleSize))
                            .foregroundStyle(AerieColor.text3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                trailing()
            }
        }
    }
}

extension SettingsPageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil, subtitleSize: CGFloat = 13) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, subtitleSize: subtitleSize, trailing: { EmptyView() })
    }
}

/// `.dot` — a 7pt status dot with the design's tone glow.
struct SettingsDot: View {
    enum Tone { case ok, warn, err, amber, muted }
    var tone: Tone = .ok
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: tone == .muted ? .clear : color.opacity(0.85), radius: size >= 7 ? 5 : 0)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch tone {
        case .ok:    return AerieColor.ok
        case .warn:  return AerieColor.warn
        case .err:   return AerieColor.crimsonHot
        case .amber: return AerieColor.amber
        case .muted: return AerieColor.text4
        }
    }
}

/// A keycap for shortcut hints: min 20×20, 0/5 padding, 2pt radius,
/// black/0.30 fill, glass hairline, faint inset top highlight, mono 12 text-2.
struct HudKeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .aerieFont(AerieFont.code(12))
            .foregroundStyle(AerieColor.text2)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(Color.black.opacity(0.30))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 1).padding(.top, 1)
            }
            .fixedSize()
    }
}

extension View {
    /// A recessed well / command box: black fill (0.32 by default), 1px glass
    /// hairline, 2pt radius.
    func hudWell(fill: Double = 0.32, line: Color = AerieColor.glassLine) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(Color.black.opacity(fill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(line, lineWidth: 1)
            )
    }
}

/// The design's toggle (`mcp.jsx`): a 38×22 pill with 2pt padding. On: gold
/// fill, gold-line rim, 12pt gold glow, 16pt white knob on the right. Off:
/// glass-3 fill, glass-line-2 rim, text-2 knob on the left. 200ms slide.
/// Keeps toggle semantics for VoiceOver via `accessibilityRepresentation`.
struct AerieToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? AerieColor.amber : AerieColor.glass3)
                Capsule()
                    .strokeBorder(on ? AerieColor.amberLine : AerieColor.glassLine2, lineWidth: 1)
                Circle()
                    .fill(on ? Color.white : AerieColor.text2)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .padding(3)
            }
            .frame(width: 38, height: 22)
            .shadow(color: on ? AerieColor.amber.opacity(0.4) : .clear, radius: 6)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.2), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == AerieToggleStyle {
    static var aerie: AerieToggleStyle { AerieToggleStyle() }
}
