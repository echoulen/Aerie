import SwiftUI

/// Custom 44 pt titlebar that sits flush under the native title bar (which
/// is made transparent via `aerieWindowChrome()`). The native macOS traffic
/// light buttons remain visible at top-left and overlay this view's leading
/// inset — we reserve `nativeTrafficLightsInset` for them rather than
/// redrawing our own.
///
/// Layout (left → right):
///   [ native-buttons inset 72pt ]  [ BrandMark ]  24pt  [ mid ]  Spacer  [ trail ]
///
/// `mid` and `trail` are generic slots so callers can drop in
/// `SegmentedToggle`, `LiveIndicator`, etc. without changing this contract.
struct Titlebar<Mid: View, Trail: View>: View {
    @ViewBuilder var mid: () -> Mid
    @ViewBuilder var trail: () -> Trail

    /// Width reserved for the native macOS traffic light cluster
    /// (close/min/zoom: 3 × 12pt buttons + 2 × 8pt gaps + ~13pt left padding
    /// + a little breathing room).
    private static var nativeTrafficLightsInset: CGFloat { 72 }

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Self.nativeTrafficLightsInset)
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
