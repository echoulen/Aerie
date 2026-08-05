import SwiftUI

/// Lightweight confirmation content anchored to a trigger button via
/// `.popover(isPresented:)`. Reuses `DialogTone` (from `DialogShell.swift`)
/// for tone-appropriate icon/accent colours, but — unlike `DialogShell` —
/// carries no busy/error state of its own: confirming closes the popover
/// immediately and hands off to a background action store (`PRActionStore` /
/// `RepoActionStore`), which reports failure via an `ActionErrorStrip` under
/// the row instead of an in-dialog banner. The popover host supplies
/// dismiss-on-outside-click / Esc for free, so there's no scrim or
/// `onExitCommand` handling here either.
struct ActionPopoverShell<Content: View>: View {
    let tone: DialogTone
    let title: String
    let subtitle: String?
    let primaryTitle: String
    let onPrimary: () -> Void
    let secondaryTitle: String
    let onSecondary: () -> Void
    var primaryDisabled: Bool = false
    var icon: String? = nil
    var iconView: AnyView? = nil
    var primaryProminent: Bool = false
    var headerSpacing: CGFloat = 4
    var titleWeight: Font.Weight = .medium
    @ViewBuilder var content: () -> Content

    @State private var secondaryHover = false
    @State private var primaryHover = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                content()
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)
            footer
        }
        .frame(width: 460)
        .glass(.dialog)
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusDialog, style: .continuous)
                .strokeBorder(ringColor, lineWidth: 1.5)
                .opacity(tone == .neutral ? 0 : 1)
        )
        // Same fix `DialogShell` needed: system controls embedded in the
        // content (e.g. `DialogApprove`'s `TextField`/`Menu`) don't reliably
        // inherit the window's forced dark appearance inside an overlay/
        // popover, and paint invisible light-mode text otherwise.
        .environment(\.colorScheme, .dark)
    }

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
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ringColor, lineWidth: 1))
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

    private var ringColor: Color {
        switch tone {
        case .danger: return AerieColor.err.opacity(0.5)
        case .warning: return AerieColor.amberLine
        case .neutral: return AerieColor.glassLine
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 8)
            cancelButton
            primaryButton
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(AerieColor.dialogFooter)
        .overlay(Rectangle().fill(AerieColor.glassLine).frame(height: 1), alignment: .top)
    }

    private var cancelButton: some View {
        Button(action: onSecondary) {
            Text(secondaryTitle)
                .aerieFont(AerieFont.small())
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(secondaryHover ? AerieColor.text1 : AerieColor.text3)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(secondaryHover ? AerieColor.glass2 : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { secondaryHover = $0 }
        .animation(.easeOut(duration: 0.18), value: secondaryHover)
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            Text(primaryTitle)
                .aerieFont(AerieFont.small().weight(primaryProminent ? .semibold : .medium))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(primaryTextColor)
                .background(primaryButtonBackground)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(primaryStroke, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(primaryDisabled)
        .opacity(primaryDisabled ? 0.5 : 1)
        .onHover { primaryHover = primaryDisabled ? false : $0 }
        .animation(.easeOut(duration: 0.18), value: primaryHover)
    }

    @ViewBuilder
    private var primaryButtonBackground: some View {
        if primaryProminent {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [AerieColor.amberFillTop, AerieColor.amberFillBot], startPoint: .top, endPoint: .bottom))
                .brightness(primaryHover ? 0.04 : 0)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(primaryFill)
        }
    }

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
