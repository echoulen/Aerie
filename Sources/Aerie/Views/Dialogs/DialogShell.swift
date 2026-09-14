import SwiftUI

/// Tone drives the dialog's accent ring and icon tile (the design's `tone`).
enum DialogTone: Equatable {
    case danger    // crimson ring + crimson icon tile
    case warning   // gold ring + gold icon tile (the design's `amber` tone)
    case neutral   // glass-line-2 ring, neutral icon tile
}

// MARK: - Tone styling (`v2/dialogs.jsx` `Dialog`)

extension DialogTone {
    /// `accentRing` — the card's 1pt border and the icon tile's border.
    var accentRing: Color {
        switch self {
        case .danger:  return AerieColor.crimsonLine
        case .warning: return AerieColor.amberLine
        case .neutral: return AerieColor.glassLine2
        }
    }

    var iconBackground: Color {
        switch self {
        case .danger:  return AerieColor.crimson.opacity(0.18)
        case .warning: return AerieColor.amberSoft
        case .neutral: return AerieColor.glass2
        }
    }

    var iconColor: Color {
        switch self {
        case .danger:  return AerieColor.crimsonHot
        case .warning: return AerieColor.amber
        case .neutral: return AerieColor.text2
        }
    }

    var defaultIcon: String {
        switch self {
        case .danger:  return "exclamationmark.triangle"
        case .warning: return "arrow.triangle.merge"
        case .neutral: return "info.circle"
        }
    }

    /// The design's default `primaryVariant` for a tone: danger dialogs get a
    /// `.btn.danger`, gold dialogs the `.btn.amber` CTA, neutral a plain `.btn`.
    var defaultPrimaryVariant: HudButtonStyle.Kind {
        switch self {
        case .danger:  return .danger
        case .warning: return .amber
        case .neutral: return .standard
        }
    }
}

/// The dialog card surface — `rgba(28, 26, 32, 0.78)` over a heavy blur.
private let dialogCardSurface = Color(red: 28/255, green: 26/255, blue: 32/255)

/// A `.hud-note` with a caller-chosen text colour (the design tints some notes,
/// e.g. the arc "request" label or a crimson "irreversible" warning).
struct DialogNote: View {
    let text: String
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
        }
        .fixedSize()
    }
}

/// The shared confirmation card (`v2/dialogs.jsx` `Dialog`): a 520pt, 3pt-radius
/// glass card bordered in the tone's accent ring, a 36pt icon tile + 17pt title
/// header, caller content, and a recessed footer with a ghost Cancel and the
/// `primaryVariant` button. While `loading`, a `.progress-track` sits between
/// the body and the footer (replacing the footer's top border), the footer
/// shows a spinner + `progressNote` on the left, and the primary shows a
/// spinner + `loadingLabel`. Rendered by both `DialogShell` (modal, with scrim)
/// and `ActionPopoverShell` (popover).
struct DialogCard<Content: View>: View {
    let tone: DialogTone
    let title: String
    let subtitle: String?
    let primaryTitle: String
    let onPrimary: () -> Void
    let secondaryTitle: String
    let onSecondary: () -> Void
    var primaryDisabled: Bool = false
    var primaryVariant: HudButtonStyle.Kind? = nil
    var loading: Bool = false
    var loadingLabel: String? = nil
    var progressNote: String? = nil
    var errorMessage: String? = nil
    var icon: String? = nil
    var iconView: AnyView? = nil
    var width: CGFloat = 520
    @ViewBuilder var content: () -> Content

    private var variant: HudButtonStyle.Kind { primaryVariant ?? tone.defaultPrimaryVariant }
    private var isDangerVariant: Bool { variant == .danger }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                content()
                if let msg = errorMessage {
                    DialogErrorStrip(message: msg)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            if loading {
                ProgressSweep(tone: isDangerVariant ? .danger : .amber)
            }
            footer
        }
        .frame(width: width)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                dialogCardSurface.opacity(0.78)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AerieMetric.radiusDialog, style: .continuous))
        // `inset 0 1px 0 0 var(--glass-highlight)` — a bright top edge.
        .overlay(alignment: .top) {
            Rectangle().fill(AerieColor.glassHighlight).frame(height: 1)
                .padding(.horizontal, 1)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusDialog, style: .continuous)
                .strokeBorder(tone.accentRing, lineWidth: 1)
                .allowsHitTesting(false)
        )
        // `0 30px 80px -20px rgba(0,0,0,0.7)`
        .shadow(color: .black.opacity(0.7), radius: 30, y: 30)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .fill(tone.iconBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                        .strokeBorder(tone.accentRing, lineWidth: 1)
                )
                .frame(width: 36, height: 36)
                .overlay(iconGlyph)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .aerieFont(AerieFont.custom(.sans, size: 17).weight(.medium))
                    .tracking(-0.085)
                    .foregroundStyle(AerieColor.text1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .aerieFont(AerieFont.custom(.sans, size: 13))
                        .foregroundStyle(AerieColor.text3)
                        .lineSpacing(3.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var iconGlyph: some View {
        if let iconView {
            iconView
        } else {
            Image(systemName: icon ?? tone.defaultIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tone.iconColor)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if loading, let progressNote {
                HStack(spacing: 8) {
                    DialogSpinner(stroke: isDangerVariant ? AerieColor.crimsonHot : AerieColor.amber)
                    Text(progressNote)
                        .aerieFont(AerieFont.custom(.sans, size: 12.5))
                        .foregroundStyle(AerieColor.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            // `.btn.ghost`; `disabled` while loading at opacity 0.4.
            Button(secondaryTitle, action: onSecondary)
                .buttonStyle(.hud(.ghost))
                .disabled(loading)
                .opacity(loading ? 0.4 / 0.45 : 1)
            primaryButton
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .top) {
            if !loading {
                Rectangle().fill(AerieColor.glassLine).frame(height: 1)
            }
        }
    }

    // `.btn.<primaryVariant>`. While loading the design keeps the variant's
    // colour at opacity 0.85 (a disabled `HudButtonStyle` would dim to 0.45), so
    // clicks are swallowed instead of disabling; a 13pt spinner (white on
    // danger, amber-ink on gold) leads the `loadingLabel`.
    private var primaryButton: some View {
        Button {
            if !loading { onPrimary() }
        } label: {
            HStack(spacing: 8) {
                if loading {
                    DialogSpinner(stroke: isDangerVariant ? .white : AerieColor.amberInk)
                }
                Text(DialogShell<EmptyView>.primaryLabel(
                    loading: loading, loadingLabel: loadingLabel, primaryTitle: primaryTitle
                ))
            }
        }
        .buttonStyle(.hud(variant))
        .disabled(primaryDisabled)
        .allowsHitTesting(!loading)
        .opacity(loading ? 0.85 : 1)
    }
}

/// Modal dialog scaffold used by Aerie's confirmation dialogs (sign-out,
/// remove-repo, MCP request). Renders a 0.45 black scrim with the shared
/// `DialogCard` centred on top.
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
    /// The primary button's `.btn` variant; nil derives it from `tone`
    /// (see `DialogTone.defaultPrimaryVariant`).
    var primaryVariant: HudButtonStyle.Kind? = nil
    /// Drives the shared loading state (see `DialogCard`).
    var loading: Bool = false
    /// Primary-button label while `loading` (e.g. "Resetting…" / "Merging…").
    /// Falls back to `primaryTitle` when nil.
    var loadingLabel: String? = nil
    /// Status text beside the footer's leading spinner while `loading`. Nil hides
    /// the leading group, leaving the buttons trailing-aligned.
    var progressNote: String? = nil
    /// Error strip shown below the content; nil hides it.
    var errorMessage: String? = nil
    /// SF Symbol for the header icon. Defaults to a tone-appropriate glyph.
    var icon: String? = nil
    /// A custom header glyph that overrides `icon` when set.
    var iconView: AnyView? = nil
    /// Opt-in light-dismiss: when set, a click on the scrim or the Esc key calls
    /// this. Automatically ignored while `loading` so an in-flight op can't be
    /// dismissed. Nil (the default) leaves the dialog modal.
    var onBackgroundDismiss: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    // MARK: - Loading presentation (pure, unit-testable)

    /// The primary button's label: while loading, the `loadingLabel` (falling
    /// back to the idle `primaryTitle` when nil); otherwise `primaryTitle`.
    static func primaryLabel(
        loading: Bool, loadingLabel: String?, primaryTitle: String
    ) -> String {
        loading ? (loadingLabel ?? primaryTitle) : primaryTitle
    }

    /// Accent tinting the progress track + footer spinner: destructive dialogs
    /// read crimson, every other tone reads gold. Static + testable.
    static func loadingAccent(for tone: DialogTone) -> Color {
        tone == .danger ? AerieColor.err : AerieColor.amber
    }

    var body: some View {
        ZStack {
            scrim
            DialogCard(
                tone: tone, title: title, subtitle: subtitle,
                primaryTitle: primaryTitle, onPrimary: onPrimary,
                secondaryTitle: secondaryTitle, onSecondary: onSecondary,
                primaryDisabled: primaryDisabled, primaryVariant: primaryVariant,
                loading: loading, loadingLabel: loadingLabel, progressNote: progressNote,
                errorMessage: errorMessage, icon: icon, iconView: iconView,
                content: content
            )
        }
        .ignoresSafeArea()
        // Lock the dialog subtree to dark. System-rendered controls inside
        // dialogs (a `Menu` label, a `TextField` placeholder) resolve their
        // text against the *effective* appearance, which the window-level
        // dark lock doesn't reliably reach inside overlays.
        .environment(\.colorScheme, .dark)
        // Esc closes the dialog when light-dismiss is enabled and nothing is
        // in flight. No-op otherwise (keeps the other dialogs modal).
        .onExitCommand { if let onBackgroundDismiss, !loading { onBackgroundDismiss() } }
    }

    // `rgba(0,0,0,0.45)` scrim. When light-dismiss is enabled, a click on the
    // scrim closes the dialog (unless an op is in flight).
    @ViewBuilder
    private var scrim: some View {
        if let onBackgroundDismiss {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { if !loading { onBackgroundDismiss() } }
        } else {
            Color.black.opacity(0.45)
        }
    }
}

/// In-dialog error strip — the `.wt-merge-error` treatment: 2pt radius,
/// crimson-line border on a crimson-soft wash.
struct DialogErrorStrip: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AerieColor.crimsonHot)
            Text(message)
                .aerieFont(AerieFont.custom(.sans, size: 12))
                .foregroundStyle(AerieColor.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).fill(AerieColor.crimsonSoft))
        .overlay(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).strokeBorder(AerieColor.crimsonLine, lineWidth: 1))
    }
}

/// Small inline loading spinner — the design's `.spinner`: a 2pt ring with the
/// top and right quarters transparent, rotating 0.7s linear, with a soft
/// `drop-shadow(0 0 4px currentColor)`.
struct DialogSpinner: View {
    var stroke: Color
    var size: CGFloat = 13

    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.5)
            .stroke(stroke, lineWidth: 2)
            .shadow(color: stroke.opacity(0.8), radius: 2)
            .frame(width: size - 2, height: size - 2)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(
                .linear(duration: 0.7).repeatForever(autoreverses: false),
                value: spinning
            )
            .onAppear { spinning = true }
    }
}
