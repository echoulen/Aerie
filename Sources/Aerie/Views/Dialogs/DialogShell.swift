import SwiftUI

/// Tone drives the accent color used for the title ring and primary button.
enum DialogTone: Equatable {
    case danger    // red ring, red primary
    case warning   // amber ring, amber primary (used for merges)
    case neutral   // plain glass, neutral primary
}

/// Modal dialog scaffold used by Aerie's confirmation dialogs (reset, merge,
/// sign-out, remove-repo). Renders a scrim, a glass card with a header, the
/// caller-provided content, an optional error banner, and a footer with
/// secondary + primary buttons. The `tone` decides the ring color and primary
/// button accent (danger=red, warning=amber, neutral=glass).
struct DialogShell<Content: View>: View {
    let tone: DialogTone
    let title: String
    let subtitle: String?
    let primaryTitle: String
    let onPrimary: () -> Void
    let secondaryTitle: String
    let onSecondary: () -> Void
    /// Disable the primary button while an action is in-flight.
    var primaryDisabled: Bool = false
    /// Error banner shown above the buttons; nil hides it.
    var errorMessage: String? = nil
    /// SF Symbol for the header icon. Defaults to a tone-appropriate glyph.
    var icon: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            scrim
            card
        }
        .ignoresSafeArea()
    }

    // Pure dark scrim — `.ultraThinMaterial` brightens the area in dark mode
    // (the "dialog looks too white" symptom), so we drop it and rely on the
    // parent's natural darkness. 0.45 matches design `rgba(0,0,0,0.45)`.
    private var scrim: some View {
        Color.black.opacity(0.45)
    }

    private var card: some View {
        VStack(spacing: 0) {
            // Header + content share one padded block (no internal divider —
            // the only separator in the design is the footer band).
            VStack(alignment: .leading, spacing: 18) {
                header
                content()
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 18)
            if let msg = errorMessage {
                errorBanner(msg)
            }
            footer
        }
        .frame(width: 520)
        // Dark dialog surface (replaces `.regularMaterial`, which read milky
        // on the dimmed scrim). For danger/warning tones we layer a coloured
        // ring on top of the default glass-line-2 border.
        .glass(.dialog)
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusDialog, style: .continuous)
                .strokeBorder(ringColor, lineWidth: 1.5)
                .opacity(tone == .neutral ? 0 : 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
    }

    // Header — a tone-coloured icon tile beside the title + subtitle, matching
    // the design's `Dialog` header (36pt icon, 17pt medium title).
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            iconTile
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .aerieFont(AerieFont.custom(.sans, size: 17).weight(.medium))
                    .foregroundStyle(AerieColor.text1)
                if let subtitle {
                    Text(subtitle)
                        .aerieFont(AerieFont.custom(.sans, size: 13))
                        .foregroundStyle(AerieColor.text3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(iconBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ringColor, lineWidth: 1)
            )
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: icon ?? defaultIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor)
            )
    }

    private var defaultIcon: String {
        switch tone {
        case .danger:  return "exclamationmark.triangle"
        case .warning: return "arrow.triangle.merge"
        case .neutral: return "info.circle"
        }
    }

    private var iconBg: Color {
        switch tone {
        case .danger:  return AerieColor.err.opacity(0.18)
        case .warning: return AerieColor.amberSoft
        case .neutral: return AerieColor.glass2
        }
    }

    private var iconColor: Color {
        switch tone {
        case .danger:  return AerieColor.dangerText
        case .warning: return AerieColor.amber
        case .neutral: return AerieColor.text2
        }
    }

    // Footer — a recessed band (dark fill + top hairline) per the design, so it
    // reads as distinct from the body now that the middle divider is gone.
    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: onSecondary) {
                Text(secondaryTitle)
                    .aerieFont(AerieFont.small())
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(AerieColor.text2)
                    .background(Capsule().fill(AerieColor.glass1))
                    .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: onPrimary) {
                Text(primaryTitle)
                    .aerieFont(AerieFont.small().weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(primaryTextColor)
                    .background(Capsule().fill(primaryFill))
                    .overlay(Capsule().strokeBorder(primaryStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled)
            .opacity(primaryDisabled ? 0.5 : 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(AerieColor.dialogFooter)
        .overlay(
            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(height: 1),
            alignment: .top
        )
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AerieColor.err)
            Text(msg)
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AerieColor.err.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(AerieColor.err.opacity(0.4))
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .top)
        )
    }

    private var ringColor: Color {
        switch tone {
        case .danger: return AerieColor.err.opacity(0.5)
        case .warning: return AerieColor.amberLine
        case .neutral: return AerieColor.glassLine
        }
    }

    private var primaryFill: Color {
        switch tone {
        case .danger: return AerieColor.err.opacity(0.15)
        case .warning: return AerieColor.amberSoft
        case .neutral: return AerieColor.glass2
        }
    }

    private var primaryStroke: Color {
        switch tone {
        case .danger: return AerieColor.err.opacity(0.5)
        case .warning: return AerieColor.amberLine
        case .neutral: return AerieColor.glassLine
        }
    }

    private var primaryTextColor: Color {
        switch tone {
        case .danger: return AerieColor.err
        case .warning: return AerieColor.amber
        case .neutral: return AerieColor.text1
        }
    }
}
