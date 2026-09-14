import SwiftUI

/// Tone drives the accent color used for the plate ring, icon key and primary
/// button.
enum DialogTone: Equatable {
    case danger    // crimson ring, crimson `.btn.danger` primary
    case warning   // gold ring (used for merges / approvals / safe checkouts)
    case neutral   // plain plate, neutral `.btn` primary
}

// MARK: - Tone styling shared by `DialogShell` + `ActionPopoverShell`

extension DialogTone {
    /// Coloured hairline laid over the chamfered plate edge (hidden for neutral).
    var ringColor: Color {
        switch self {
        case .danger:  return AerieColor.crimsonLine
        case .warning: return AerieColor.amberLine
        case .neutral: return AerieColor.glassLine
        }
    }

    /// `.hud-corners` bracket colour — crimson on destructive plates, gold otherwise.
    var cornerColor: Color {
        self == .danger ? AerieColor.crimsonLine : AerieColor.amberLine
    }

    var iconBackground: Color {
        switch self {
        case .danger:  return AerieColor.crimsonSoft
        case .warning: return AerieColor.amberSoft
        case .neutral: return AerieColor.glass2
        }
    }

    var iconColor: Color {
        switch self {
        case .danger:  return AerieColor.dangerText
        case .warning: return AerieColor.amber
        case .neutral: return AerieColor.text2
        }
    }

    var iconGlow: Color {
        switch self {
        case .danger:  return AerieColor.crimson.opacity(0.35)
        case .warning: return AerieColor.amberGlow.opacity(0.30)
        case .neutral: return .clear
        }
    }

    var defaultIcon: String {
        switch self {
        case .danger:  return "exclamationmark.triangle"
        case .warning: return "arrow.triangle.merge"
        case .neutral: return "info.circle"
        }
    }

    /// The `HudButtonStyle` kind of the primary action. `prominent` promotes it
    /// to the gold `.btn.amber` CTA (merge / approve / safe checkout).
    func primaryButtonKind(prominent: Bool) -> HudButtonStyle.Kind {
        if prominent { return .amber }
        return self == .danger ? .danger : .standard
    }
}

/// The primary button's ink for a given `HudButtonStyle` kind — used to tint the
/// in-button loading spinner so it matches the label.
private func hudInk(for kind: HudButtonStyle.Kind) -> Color {
    switch kind {
    case .amber:  return AerieColor.amberInk
    case .danger: return AerieColor.crimsonHot
    case .arc:    return AerieColor.arc
    case .standard, .ghost: return AerieColor.text1
    }
}

/// The dialog header's icon key: a small bevelled HUD key (TL + BR cut) tinted
/// to the tone, with a soft emitted glow.
struct DialogIconTile: View {
    let tone: DialogTone
    var icon: String? = nil
    var iconView: AnyView? = nil

    var body: some View {
        let shape = HudKeyShape(cut: 8)
        shape
            .fill(tone.iconBackground)
            .overlay(shape.strokeBorder(tone.ringColor, lineWidth: 1))
            .frame(width: 36, height: 36)
            .shadow(color: tone.iconGlow, radius: 8)
            .overlay(glyph)
    }

    @ViewBuilder
    private var glyph: some View {
        if let iconView {
            iconView
        } else {
            Image(systemName: icon ?? tone.defaultIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tone.iconColor)
        }
    }
}

/// Header block shared by both dialog shells: icon key beside the title +
/// subtitle.
struct DialogHeader: View {
    let tone: DialogTone
    let title: String
    let subtitle: String?
    var icon: String? = nil
    var iconView: AnyView? = nil
    var spacing: CGFloat = 4
    var titleWeight: Font.Weight = .medium

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DialogIconTile(tone: tone, icon: icon, iconView: iconView)
            VStack(alignment: .leading, spacing: spacing) {
                Text(title)
                    .aerieFont(AerieFont.custom(.sans, size: 15.5).weight(titleWeight))
                    .tracking(0.2)
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
}

/// Chamfered-plate decoration shared by both shells: the tone ring over the
/// plate edge, `.hud-corners` brackets, and the plate's drop shadow.
struct DialogPlateChrome: ViewModifier {
    let tone: DialogTone

    func body(content: Content) -> some View {
        content
            .overlay(
                HudPlateShape(cut: AerieMetric.cutDialog)
                    .strokeBorder(tone.ringColor, lineWidth: 1)
                    .opacity(tone == .neutral ? 0 : 1)
                    .allowsHitTesting(false)
            )
            .overlay(
                HudCorners(length: 12, color: tone.cornerColor)
                    .padding(7)
            )
    }
}

/// The recessed footer band: dark fill, a top hairline and a faint tick rail
/// (`.hud-rail`) along its leading edge.
struct DialogFooterBand: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AerieColor.dialogFooter)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(AerieColor.glassLine).frame(height: 1)
                    HudRail(height: 4)
                        .frame(width: 132)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                }
                .allowsHitTesting(false)
            }
    }
}

/// Modal dialog scaffold used by Aerie's confirmation dialogs (sign-out,
/// remove-repo, MCP consent / request). Renders a scrim, a chamfered MARK III
/// HUD plate with a header, the caller-provided content, an optional error
/// strip, and a footer with secondary + primary buttons. The `tone` decides
/// the ring colour and primary button (danger = crimson, warning = gold,
/// neutral = plain plate).
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
    /// Drives the shared loading state.
    /// While true: the primary button shows a spinner + `loadingLabel` (keeping
    /// its crimson/gold colour) and ignores clicks; Cancel dims + disables; a
    /// `ProgressSweep` runs along the footer's top edge (crimson for danger,
    /// gold otherwise); and a spinner + `progressNote` appear at the footer's
    /// leading edge. The body is untouched.
    var loading: Bool = false
    /// Primary-button label while `loading` (e.g. "Resetting…" / "Merging…").
    /// Falls back to `primaryTitle` when nil.
    var loadingLabel: String? = nil
    /// Status text beside the footer's leading spinner while `loading`. Nil hides
    /// the leading group, leaving the buttons trailing-aligned.
    var progressNote: String? = nil
    /// Error strip shown above the buttons; nil hides it.
    var errorMessage: String? = nil
    /// SF Symbol for the header icon. Defaults to a tone-appropriate glyph.
    var icon: String? = nil
    /// A custom header glyph that overrides `icon` when set. Rendered inside
    /// the tone-coloured icon key.
    var iconView: AnyView? = nil
    /// Render the primary button as the gold `.btn.amber` CTA instead of the
    /// tone button.
    var primaryProminent: Bool = false
    /// Vertical gap between the title and the subtitle in the header.
    var headerSpacing: CGFloat = 4
    /// Weight of the title text.
    var titleWeight: Font.Weight = .medium
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

    /// Accent tinting the footer sweep + footer-leading spinner: destructive
    /// running states read crimson, every other tone reads gold. Static +
    /// testable.
    static func loadingAccent(for tone: DialogTone) -> Color {
        tone == .danger ? AerieColor.err : AerieColor.amber
    }

    var body: some View {
        ZStack {
            scrim
            card
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

    // Pure dark scrim (0.45 black). When light-dismiss is enabled, a click on
    // the scrim closes the dialog (unless an op is in flight).
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

    private var card: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                DialogHeader(
                    tone: tone, title: title, subtitle: subtitle,
                    icon: icon, iconView: iconView,
                    spacing: headerSpacing, titleWeight: titleWeight
                )
                content()
                if let msg = errorMessage {
                    DialogErrorStrip(message: msg)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 18)
            footer
        }
        .frame(width: 520)
        .glass(.dialog)
        .modifier(DialogPlateChrome(tone: tone))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if loading, let progressNote {
                HStack(spacing: 9) {
                    DialogSpinner(stroke: loadingAccentColor)
                    Text(progressNote)
                        .aerieFont(AerieFont.code(11))
                        .tracking(0.4)
                        .foregroundStyle(AerieColor.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Button(secondaryTitle, action: onSecondary)
                .buttonStyle(.hud(.ghost))
                .disabled(loading)
            primaryButton
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .modifier(DialogFooterBand())
        .overlay(alignment: .top) {
            if loading {
                ProgressSweep(tone: tone == .danger ? .danger : .amber)
            }
        }
    }

    private var loadingAccentColor: Color { Self.loadingAccent(for: tone) }

    // Primary — the tone's `HudButtonStyle`. While loading it keeps its colour
    // (a disabled `HudButtonStyle` would dim to "blocked"), prepends a spinner
    // in the button's own ink, and swallows clicks.
    private var primaryButton: some View {
        let kind = tone.primaryButtonKind(prominent: primaryProminent)
        return Button {
            if !loading { onPrimary() }
        } label: {
            HStack(spacing: 8) {
                if loading {
                    DialogSpinner(stroke: hudInk(for: kind))
                }
                Text(Self.primaryLabel(
                    loading: loading, loadingLabel: loadingLabel, primaryTitle: primaryTitle
                ))
            }
        }
        .buttonStyle(.hud(kind))
        .disabled(primaryDisabled)
        .allowsHitTesting(!loading)
        .opacity(loading ? 0.9 : 1)
    }
}

/// In-dialog error strip: a crimson-washed square plate with a hot crimson
/// strut down its leading edge.
struct DialogErrorStrip: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AerieColor.err)
            Text(message)
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .crimsonStrip()
    }
}

extension View {
    /// Crimson error plate — `crimsonSoft` wash, `crimsonLine` hairline and a
    /// 2pt `crimsonHot` strut on the leading edge.
    func crimsonStrip() -> some View {
        let shape = RoundedRectangle(cornerRadius: AerieMetric.radiusCard, style: .continuous)
        return self
            .background(shape.fill(AerieColor.crimsonSoft))
            .overlay(shape.strokeBorder(AerieColor.crimsonLine, lineWidth: 1))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AerieColor.crimsonHot)
                    .frame(width: 2)
                    .shadow(color: AerieColor.crimson.opacity(0.6), radius: 4)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
            }
    }
}

/// Small inline loading spinner — the `.spinner` primitive: a thin ring with a
/// bright quarter arc rotating continuously (0.7s linear, infinite).
struct DialogSpinner: View {
    var stroke: Color
    var size: CGFloat = 13

    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(stroke.opacity(0.22), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
                .shadow(color: stroke.opacity(0.6), radius: 3)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(
            .linear(duration: 0.7).repeatForever(autoreverses: false),
            value: spinning
        )
        .onAppear { spinning = true }
    }
}
