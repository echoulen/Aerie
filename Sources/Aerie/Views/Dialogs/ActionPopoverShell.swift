import SwiftUI

/// Lightweight confirmation content anchored to a trigger button via
/// `.popover(isPresented:)`. Shares `DialogShell`'s MARK III chrome — the
/// chamfered HUD plate, tone ring, corner brackets, icon key and footer band
/// (see `DialogShell.swift`) — but carries no busy/error state of its own:
/// confirming closes the popover immediately and hands off to a background
/// action store (`PRActionStore` / `RepoActionStore`), which reports failure via
/// an `ActionErrorStrip` under the row instead of an in-dialog banner. The
/// popover host supplies dismiss-on-outside-click / Esc for free, so there's no
/// scrim or `onExitCommand` handling here either.
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
    /// Promote the primary to the gold `.btn.amber` CTA.
    var primaryProminent: Bool = false
    var headerSpacing: CGFloat = 4
    var titleWeight: Font.Weight = .medium
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                DialogHeader(
                    tone: tone, title: title, subtitle: subtitle,
                    icon: icon, iconView: iconView,
                    spacing: headerSpacing, titleWeight: titleWeight
                )
                content()
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)
            footer
        }
        .frame(width: 460)
        .glass(.dialog)
        .modifier(DialogPlateChrome(tone: tone))
        // Same fix `DialogShell` needed: system controls embedded in the
        // content (e.g. `DialogApprove`'s `TextField`/`Menu`) don't reliably
        // inherit the window's forced dark appearance inside an overlay/
        // popover, and paint invisible light-mode text otherwise.
        .environment(\.colorScheme, .dark)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 8)
            Button(secondaryTitle, action: onSecondary)
                .buttonStyle(.hud(.ghost))
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.hud(tone.primaryButtonKind(prominent: primaryProminent)))
                .disabled(primaryDisabled)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .modifier(DialogFooterBand())
    }
}
