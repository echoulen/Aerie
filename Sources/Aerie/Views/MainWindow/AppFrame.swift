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
        .frame(minWidth: AerieMetric.mainWindowW, minHeight: AerieMetric.mainWindowH)
    }
}
