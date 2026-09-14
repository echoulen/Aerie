import SwiftUI

// MARK III building blocks shared by the Settings screens. Everything here is
// composed from the design-system primitives (`SectionEyebrow`, `HudKeyShape`,
// `AerieColor`, …) so the Settings pages speak the same HUD language as the
// main window without each screen re-deriving the styling.
// Design source: `src/v2/settings.jsx` + `styles.css`
// (`.section-eyebrow`, `.section-title`, `.kbd`, `.switch`, `.field`).

/// A Settings page header — the Settings twin of the main window's
/// `PageHeader`: a gold mono eyebrow over a 27pt semibold title with the
/// `.section-title` gold text-shadow, a mono subtitle on the title baseline,
/// and an optional trailing action cluster.
struct SettingsPageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(text: eyebrow)
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
                        .aerieFont(AerieFont.code(13))
                        .tracking(0.26)              // 0.02em @ 13pt
                        .foregroundStyle(AerieColor.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 16)
                trailing()
            }
        }
    }
}

extension SettingsPageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// An in-page section label: an uppercase mono overline followed by a gold
/// hairline that fades out across the column — the HUD "bus" that each card
/// group hangs off. An optional `live` flag adds the arc-cyan pulse used for
/// sections fed by live polling (e.g. rate limits).
struct SettingsSectionLabel: View {
    let text: String
    var live: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(text.uppercased())
                .aerieFont(AerieFont.eyebrow())
                .tracking(2.6)                       // 0.26em @ 10pt
                .foregroundStyle(AerieColor.text3)
                .fixedSize()
            if live {
                LiveDot()
            }
            LinearGradient(colors: [AerieColor.amberLine, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
    }
}

/// A 6pt arc-cyan pulse. Arc is reserved for live energy — only use this for
/// state that is actually updating (polling, a running server).
struct LiveDot: View {
    var size: CGFloat = 6
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(AerieColor.arc)
            .frame(width: size, height: size)
            .shadow(color: AerieColor.arcGlow, radius: pulsing ? 6 : 3)
            .opacity(pulsing ? 0.6 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulsing = true }
            }
            .accessibilityHidden(true)
    }
}

/// `.kbd` — a small bevelled keycap for shortcut hints.
struct HudKeyCap: View {
    let key: String
    var size: CGFloat = 11

    var body: some View {
        Text(key)
            .aerieFont(AerieFont.code(size).weight(.medium))
            .foregroundStyle(AerieColor.text2)
            .frame(minWidth: size + 8)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.34), in: HudKeyShape(cut: 4))
            .overlay(HudKeyShape(cut: 4).strokeBorder(AerieColor.glassLine2, lineWidth: 1))
            .fixedSize()
    }
}

extension View {
    /// A recessed input / code well (`.field`): near-black fill, glass hairline,
    /// 2pt radius. Used for command boxes, key/value tables and editors.
    func hudWell(fill: Double = 0.32) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(Color.black.opacity(fill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )
    }
}

/// MARK III `.switch`: a squared track with a sliding gold key. Off = recessed
/// black well with a dim key; on = gold wash, gold rim and a glowing key.
/// Keeps toggle semantics for VoiceOver (`isToggle` trait + on/off value).
struct HudSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(on ? AerieColor.amberSoft : Color.black.opacity(0.40))
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(on ? AerieColor.amberLine : AerieColor.glassLine2, lineWidth: 1)
                HudKeyShape(cut: 3)
                    .fill(on
                          ? AnyShapeStyle(LinearGradient(colors: [AerieColor.amberFillTop, AerieColor.amberFillBot],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(AerieColor.text4))
                    .frame(width: 14, height: 12)
                    .shadow(color: on ? AerieColor.amberGlow.opacity(0.6) : .clear, radius: 6)
                    .padding(.horizontal, 3)
            }
            .frame(width: 36, height: 18)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.16), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == HudSwitchStyle {
    static var hud: HudSwitchStyle { HudSwitchStyle() }
}
