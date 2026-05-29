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
            header
            Divider().background(AerieColor.glassLine)
            content()
                .padding(.horizontal, 24).padding(.vertical, 20)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            if let subtitle {
                Text(subtitle)
                    .font(AerieFont.small())
                    .foregroundStyle(AerieColor.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: onSecondary) {
                Text(secondaryTitle)
                    .font(AerieFont.small())
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(AerieColor.text2)
                    .background(Capsule().fill(AerieColor.glass1))
                    .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: onPrimary) {
                Text(primaryTitle)
                    .font(AerieFont.small().weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(primaryTextColor)
                    .background(Capsule().fill(primaryFill))
                    .overlay(Capsule().strokeBorder(primaryStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled)
            .opacity(primaryDisabled ? 0.5 : 1)
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AerieColor.err)
            Text(msg)
                .font(AerieFont.small())
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
