import SwiftUI
import Combine

/// Top-level first-run view. Subscribes to a ``GhBootstrapper``'s state and
/// renders the right body based on the latest ``AuthBootstrapResult``.
///
/// Visual contract: `v2/first-run.jsx` — the body sits directly on the
/// backdrop (no card), over a warm radial wash.
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
            FirstRunWarmWash()
            content
                .padding(56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

/// The first-run warm wash: `radial-gradient(oklch(0.55 0.13 55 / 0.28))` at
/// 80% / 10% and `radial-gradient(oklch(0.45 0.13 80 / 0.18))` at 15% / 90%.
private struct FirstRunWarmWash: View {
    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * 0.6
            ZStack {
                RadialGradient(
                    colors: [Color(red: 0.70, green: 0.37, blue: 0.10).opacity(0.28), .clear],
                    center: UnitPoint(x: 0.8, y: 0.1), startRadius: 0, endRadius: r
                )
                RadialGradient(
                    colors: [Color(red: 0.50, green: 0.33, blue: 0.0).opacity(0.18), .clear],
                    center: UnitPoint(x: 0.15, y: 0.9), startRadius: 0, endRadius: r
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
