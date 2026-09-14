import SwiftUI

/// Lightweight confirmation content anchored to a trigger button via
/// `.popover(isPresented:)`. Renders the same `DialogCard` as `DialogShell`
/// (see `DialogShell.swift`) but carries no busy/error state of its own:
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
    /// The primary button's `.btn` variant; nil derives it from `tone`.
    var primaryVariant: HudButtonStyle.Kind? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        DialogCard(
            tone: tone, title: title, subtitle: subtitle,
            primaryTitle: primaryTitle, onPrimary: onPrimary,
            secondaryTitle: secondaryTitle, onSecondary: onSecondary,
            primaryDisabled: primaryDisabled, primaryVariant: primaryVariant,
            icon: icon, iconView: iconView,
            content: content
        )
        // Same fix `DialogShell` needed: system controls embedded in the
        // content (e.g. `DialogApprove`'s `TextField`/`Menu`) don't reliably
        // inherit the window's forced dark appearance inside an overlay/
        // popover, and paint invisible light-mode text otherwise.
        .environment(\.colorScheme, .dark)
    }
}
