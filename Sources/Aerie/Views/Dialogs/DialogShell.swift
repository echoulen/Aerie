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
    /// Drives the shared loading state. The Reset and Merge dialogs set it; Sign
    /// out and Remove leave it off (and keep the plain `primaryDisabled` footer).
    /// While true: the primary button shows a spinner + `loadingLabel` (keeping
    /// its danger/amber colour) and disables; Cancel dims + disables; an
    /// indeterminate progress bar sweeps along the footer's top edge; and a
    /// spinner + `progressNote` appear at the footer's leading edge. The body is
    /// untouched. The accent derives from `tone` (the design's `primaryVariant`).
    var loading: Bool = false
    /// Primary-button label while `loading` (e.g. "Resetting…" / "Merging…").
    /// Falls back to `primaryTitle` when nil.
    var loadingLabel: String? = nil
    /// Status text beside the footer's leading spinner while `loading`. Nil hides
    /// the leading group, leaving the buttons trailing-aligned.
    var progressNote: String? = nil
    /// Error banner shown above the buttons; nil hides it.
    var errorMessage: String? = nil
    /// SF Symbol for the header icon. Defaults to a tone-appropriate glyph.
    var icon: String? = nil
    /// A custom header glyph that overrides `icon` when set (e.g. the git-merge
    /// graph the merge dialog uses). Rendered inside the tone-coloured tile.
    var iconView: AnyView? = nil
    /// Render the primary button as the design's prominent `.btn.amber` CTA
    /// (bright amber gradient + dark ink) instead of the flat tone fill. Used by
    /// the merge dialog; other dialogs keep the calmer tone-tinted button.
    var primaryProminent: Bool = false
    /// Vertical gap between the title and the subtitle in the header.
    var headerSpacing: CGFloat = 4
    /// Weight of the title text. Defaults to medium (the design's 500); the
    /// merge dialog overrides to a lighter weight.
    var titleWeight: Font.Weight = .medium
    @ViewBuilder var content: () -> Content

    // Hover state for the footer buttons (the design's `.btn` family has hover
    // styles: ghost → glass-2 + text-1; danger → deeper err fill).
    @State private var secondaryHover = false
    @State private var primaryHover = false

    // MARK: - Loading presentation (pure, unit-testable)

    /// The primary button's label: while loading, the `loadingLabel` (falling
    /// back to the idle `primaryTitle` when nil); otherwise `primaryTitle`.
    /// Static so it's testable without rendering the view.
    static func primaryLabel(
        loading: Bool, loadingLabel: String?, primaryTitle: String
    ) -> String {
        loading ? (loadingLabel ?? primaryTitle) : primaryTitle
    }

    /// Accent tinting the footer progress bar + footer-leading spinner — the
    /// design's `primaryColor` derived from the tone: danger reads red, every
    /// other tone reads amber (mirrors the `primaryVariant` default). Static +
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
                if let msg = errorMessage {
                    errorBanner(msg)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 18)
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
            VStack(alignment: .leading, spacing: headerSpacing) {
                Text(title)
                    .aerieFont(AerieFont.custom(.sans, size: 15).weight(titleWeight))
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
            .overlay(iconGlyph)
    }

    @ViewBuilder
    private var iconGlyph: some View {
        if let iconView {
            iconView
        } else {
            Image(systemName: icon ?? defaultIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconColor)
        }
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
    // reads as distinct from the body now that the middle divider is gone. While
    // `loading` it also carries a leading spinner + `progressNote` and a
    // top-edge indeterminate progress bar pinned over the hairline.
    private var footer: some View {
        HStack(spacing: 8) {
            // Footer-leading status (the design's space-between layout): a spinner
            // + a calm progress note, only while loading. The `Spacer` then
            // pushes the buttons to the trailing edge.
            if loading, let progressNote {
                HStack(spacing: 9) {
                    DialogSpinner(stroke: loadingAccentColor)
                    Text(progressNote)
                        .aerieFont(AerieFont.custom(.sans, size: 12.5))
                        .foregroundStyle(AerieColor.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            cancelButton
            primaryButton
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(AerieColor.dialogFooter)
        .overlay(
            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(height: 1),
            alignment: .top
        )
        .overlay(alignment: .top) {
            if loading {
                DialogProgressBar(color: loadingAccentColor)
            }
        }
    }

    private var loadingAccentColor: Color { Self.loadingAccent(for: tone) }

    // Cancel — `.btn.ghost`: transparent at rest (a text button), and on hover
    // gains a glass-2 fill + text-1 (per the design). While loading it dims and
    // disables so the operation can't be dismissed mid-flight.
    private var cancelButton: some View {
        Button(action: onSecondary) {
            Text(secondaryTitle)
                .aerieFont(AerieFont.small())
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(secondaryHover ? AerieColor.text1 : AerieColor.text3)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(secondaryHover ? AerieColor.glass2 : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .opacity(loading ? 0.4 : 1)
        .onHover { secondaryHover = loading ? false : $0 }
        .animation(.easeOut(duration: 0.18), value: secondaryHover)
    }

    // Primary — `.btn`-family rounded rect (9pt), tone fill deepens on hover.
    // While loading it prepends a spinner (tinted to the button's own text
    // colour) and swaps the label for `loadingLabel`, keeping the tone/amber
    // fill; it disables (also honouring the standalone `primaryDisabled`).
    private var primaryButton: some View {
        let disabled = primaryDisabled || loading
        return Button(action: onPrimary) {
            HStack(spacing: 8) {
                if loading {
                    DialogSpinner(stroke: primaryTextColor)
                }
                Text(Self.primaryLabel(
                    loading: loading, loadingLabel: loadingLabel, primaryTitle: primaryTitle
                ))
                .aerieFont(AerieFont.small().weight(primaryProminent ? .semibold : .medium))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(primaryTextColor)
            .background(primaryButtonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(primaryStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        // Loading reads as "working" (0.85), plain-disabled as "blocked" (0.5),
        // fully enabled otherwise.
        .opacity(loading ? 0.85 : (primaryDisabled ? 0.5 : 1))
        .onHover { primaryHover = disabled ? false : $0 }
        .animation(.easeOut(duration: 0.18), value: primaryHover)
    }

    // A contained, inset error box (rounded, err-tinted) — not a full-width
    // band with a hard top hairline, which read as a stray red line across
    // the dialog.
    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AerieColor.err)
            Text(msg)
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AerieColor.err.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AerieColor.err.opacity(0.30), lineWidth: 1)
        )
    }

    private var ringColor: Color {
        switch tone {
        case .danger: return AerieColor.err.opacity(0.5)
        case .warning: return AerieColor.amberLine
        case .neutral: return AerieColor.glassLine
        }
    }

    // The design's prominent `.btn.amber`: a vertical amber gradient with a
    // bright inset top edge and a subtle hover brighten. Used when
    // `primaryProminent` is set (the merge dialog); other tones keep the flat
    // fill below.
    @ViewBuilder
    private var primaryButtonBackground: some View {
        if primaryProminent {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AerieColor.amberFillTop, AerieColor.amberFillBot],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.40), Color.clear],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.plusLighter)
                )
                .brightness(primaryHover ? 0.04 : 0)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(primaryFill)
        }
    }

    // Fill/stroke/text match the design's `.btn` tones; the fill deepens while
    // hovering (`.btn.danger:hover` → err/0.18, `.btn:hover` → glass-3).
    private var primaryFill: Color {
        switch tone {
        case .danger:  return primaryHover ? AerieColor.dangerFillHover : AerieColor.dangerFill
        case .warning: return primaryHover ? AerieColor.amber.opacity(0.22) : AerieColor.amberSoft
        case .neutral: return primaryHover ? AerieColor.glass3 : AerieColor.glass2
        }
    }

    private var primaryStroke: Color {
        if primaryProminent { return AerieColor.amberCtaLine }
        switch tone {
        case .danger:  return AerieColor.dangerLine
        case .warning: return AerieColor.amberLine
        case .neutral: return primaryHover ? AerieColor.glassLine2 : AerieColor.glassLine
        }
    }

    private var primaryTextColor: Color {
        if primaryProminent { return AerieColor.amberInk }
        switch tone {
        case .danger:  return AerieColor.dangerText
        case .warning: return AerieColor.amber
        case .neutral: return AerieColor.text1
        }
    }
}

/// Small inline loading spinner — the design's `.spinner` (`styles.css`): a 2pt
/// ring with a transparent quadrant, rotating continuously. Matches the shared
/// `aerie-spin` keyframe (0.7s linear, infinite), expressed as the SwiftUI
/// `rotationEffect` + `repeatForever` used elsewhere (e.g. `RefreshButton`).
struct DialogSpinner: View {
    var stroke: Color
    var size: CGFloat = 13

    @State private var spinning = false

    var body: some View {
        // A full ring at low opacity with a brighter 3/4 arc on top reads as the
        // design's "ring with one quadrant cut away" once it's rotating.
        ZStack {
            Circle()
                .stroke(stroke.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(stroke, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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

/// The footer's top-edge indeterminate progress bar — the design's
/// `.progress-track > span` (`@keyframes aerie-sweep`): a short segment that
/// sweeps left→right across a 2pt-tall clipped track. CSS runs
/// `translateX(-100% → 400%)` of the segment's own width over 1.1s ease-in-out,
/// infinite; reproduced here with an offset animation.
struct DialogProgressBar: View {
    var color: Color

    @State private var sweeping = false

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width * 0.3
            Capsule()
                .fill(color)
                .frame(width: barWidth, height: 2)
                // CSS translateX is relative to the segment's own width.
                .offset(x: sweeping ? barWidth * 4 : -barWidth)
                .animation(
                    .easeInOut(duration: 1.1).repeatForever(autoreverses: false),
                    value: sweeping
                )
        }
        .frame(height: 2)
        .clipped()
        .onAppear { sweeping = true }
    }
}
