import SwiftUI

/// The main window's outer shell: aurora `Backdrop` + custom `Titlebar`
/// (with `SegmentedToggle` in `mid` and `LiveIndicator` in `trail`) + a
/// caller-provided content slot.
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
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                Titlebar(
                    mid: { SegmentedToggle(selection: $viewModel.activeTab) },
                    trail: { LiveIndicator(nextTickInSeconds: viewModel.nextTickInSeconds) }
                )
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let toasts = toastManager {
                ToastsOverlay(manager: toasts, onViewRequest: onToastViewRequest)
            }
        }
        .frame(minWidth: AerieMetric.mainWindowW, minHeight: AerieMetric.mainWindowH)
        .aerieWindowChrome()
    }
}
