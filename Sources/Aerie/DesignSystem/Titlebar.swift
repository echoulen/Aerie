import SwiftUI

/// Custom 44 pt titlebar that replaces the native macOS title bar (hidden via
/// `.windowStyle(.hiddenTitleBar)` in `AerieApp`).
///
/// Layout (left → right):
///   [ TrafficLights ]  16pt  [ BrandMark ]  24pt  [ mid ]  Spacer  [ trail ]
///
/// `mid` and `trail` are generic slots so callers (Task 8.1+) can drop in
/// `SegmentedToggle`, `LiveIndicator`, etc. without changing this contract.
struct Titlebar<Mid: View, Trail: View>: View {
    @ViewBuilder var mid: () -> Mid
    @ViewBuilder var trail: () -> Trail

    var body: some View {
        HStack(spacing: 0) {
            TrafficLights()
            Spacer().frame(width: 16)
            BrandMark()
            Spacer().frame(width: 24)
            mid()
            Spacer(minLength: 0)
            trail()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AerieColor.glassLine)
                .frame(height: 1)
        }
    }
}

// MARK: - Convenience initializers

extension Titlebar where Trail == EmptyView {
    init(@ViewBuilder mid: @escaping () -> Mid) {
        self.init(mid: mid, trail: { EmptyView() })
    }
}

extension Titlebar where Mid == EmptyView, Trail == EmptyView {
    init() {
        self.init(mid: { EmptyView() }, trail: { EmptyView() })
    }
}
