import SwiftUI
import Combine

/// Top-level first-run view. Subscribes to a ``GhBootstrapper``'s state and
/// renders the right body based on the latest ``AuthBootstrapResult``.
///
/// Note: when `current == .ok` the parent (`AerieApp`) re-routes to the main
/// shell — this view shouldn't be visible at that point. It still renders
/// ``EmptyView`` for the brief gap between the state flipping and the parent
/// swapping us out.
struct FirstRunRoot: View {
    let bootstrapper: GhBootstrapper
    @State private var current: AuthBootstrapResult? = nil
    @State private var sub: AnyCancellable? = nil

    var body: some View {
        ZStack {
            Backdrop()
            content
                .glass(.card)
                .padding(48)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            sub = bootstrapper.state.receive(on: RunLoop.main).sink { state in
                current = state
            }
            bootstrapper.start()
        }
        .onDisappear {
            sub?.cancel()
            bootstrapper.stop()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch current {
        case .ghMissing, .none:
            NoGhBody(onRecheck: { bootstrapper.recheckNow() })
        case .noAuth:
            NoAuthBody(onRecheck: { bootstrapper.recheckNow() })
        case .ok:
            EmptyView()
        }
    }
}
