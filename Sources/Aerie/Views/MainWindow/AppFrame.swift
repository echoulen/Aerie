import SwiftUI

/// The main window's outer shell: aurora `Backdrop` + custom `Titlebar`
/// (centred brand only) + a caller-provided content slot. The view switcher
/// (`SegmentedToggle`) now lives in each screen's page header, right-aligned,
/// per the v2 design — not in the titlebar.
///
/// Design note: the v2 spec lists an "AmbientGlow" overlay alongside the
/// backdrop. We rely on `Backdrop`'s existing amber + cool-blue radial
/// gradients to satisfy that intent and do not stack a second glow layer.
struct AppFrame<Content: View>: View {
    @Bindable var viewModel: AppViewModel
    /// Optional toast manager. When non-nil, a `ToastsOverlay` is rendered
    /// in the bottom-right of the window above the content. When nil (e.g.
    /// in older snapshot tests), no overlay is added.
    var toastManager: ToastManager? = nil
    var onToastViewRequest: (ToastItem) -> Void = { _ in }
    /// When non-nil, renders the titlebar account avatar + dropdown in the
    /// top-right. Nil in tests / snapshots that don't exercise the menu.
    var accountMenu: AccountMenuViewModel? = nil
    /// Invoked when the account dropdown's "Settings…" item is chosen.
    var onOpenSettings: () -> Void = {}
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                Titlebar(title: "Aerie")
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Pull the titlebar + account-menu overlay up under the native traffic
        // lights. In a `fullSizeContentView` window SwiftUI still reserves a top
        // safe-area inset the height of the native title bar, which pushed the
        // centred brand + avatar below the window controls. `Backdrop` already
        // ignores it; the content stack and overlays must too so the 32 pt
        // titlebar starts at the window top and its 16 pt centre lines up with
        // the traffic lights.
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .bottomTrailing) {
            if let toasts = toastManager {
                ToastsOverlay(manager: toasts, onViewRequest: onToastViewRequest)
            }
        }
        // Account avatar/dropdown floats above the page content so the panel
        // isn't clipped by the titlebar.
        .overlay {
            if let accountMenu {
                AccountMenu(viewModel: accountMenu, onOpenSettings: onOpenSettings)
            }
        }
        .frame(minWidth: AerieMetric.mainWindowW, minHeight: AerieMetric.mainWindowH)
        .aerieWindowChrome()
    }
}
