import SwiftUI

/// The main window's outer shell: deep-space `Backdrop` + custom `Titlebar`
/// (centred brand only) + a caller-provided content slot, all inside the
/// MARK III chamfered hull (`.aerieHull()`). At regular width the view
/// switcher (`SegmentedToggle`) lives in each screen's page header; narrower
/// windows move it into the chrome (`compact.jsx`): the titlebar centre at
/// medium width, a tab strip under the titlebar at compact width.
///
/// The frame measures the window and publishes ``WidthClass`` to everything
/// inside it, including its own titlebar, hull and account menu.
///
/// Design note: the v2 spec lists an "AmbientGlow" overlay alongside the
/// backdrop. We rely on `Backdrop`'s own nebula washes (warm / violet / cyan)
/// to satisfy that intent and do not stack a second glow layer.
struct AppFrame<Content: View>: View {
    @Bindable var viewModel: AppViewModel
    /// When non-nil, renders the titlebar account avatar + dropdown in the
    /// top-right. Nil in tests / snapshots that don't exercise the menu.
    var accountMenu: AccountMenuViewModel? = nil
    /// Invoked when the account dropdown's "Settings…" item is chosen.
    var onOpenSettings: () -> Void = {}
    /// Update state for the titlebar pill. `.idle` (the default, and what
    /// snapshot tests get) renders nothing.
    var updatePhase: UpdatePhase = .idle
    /// Confirms + starts an in-app update. Owned by the caller because the
    /// confirmation is an AppKit alert and this view stays pure SwiftUI.
    var onInstallUpdate: () -> Void = {}
    /// Shows the message behind a failed update.
    var onShowUpdateFailure: () -> Void = {}
    /// The tab switcher for medium / compact widths. Nil hides it — e.g. while
    /// the review screen replaces the tab lists.
    var tabBar: MainTabBar? = nil
    @ViewBuilder var content: () -> Content

    @State private var widthClass: WidthClass = .regular
    @State private var widthBucket = 0
    /// The host window's width, once attached. Nil in snapshot tests, which
    /// have no window and fall back to the measured frame width.
    @State private var windowWidth: CGFloat?

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                titlebar
                if widthClass == .compact, let tabBar {
                    CompactTabStrip(bar: tabBar)
                }
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
        // Update pill sits at the titlebar's left end — clear of the window
        // lights (`Titlebar`'s `TrafficLights`: 44–93 pt, or 26–70 pt compact)
        // and opposite the account avatar. Same 11 pt top inset as the avatar, so both centre on the
        // brand's line.
        .overlay(alignment: .topLeading) {
            UpdatePill(
                phase: updatePhase,
                onInstall: onInstallUpdate,
                onShowFailure: onShowUpdateFailure
            )
            .padding(.top, 11)
            .padding(.leading, widthClass == .compact ? 88 : 108)
            .ignoresSafeArea(.container, edges: .top)
        }
        // Account avatar/dropdown floats above the page content so the panel
        // isn't clipped by the titlebar.
        .overlay {
            if let accountMenu {
                AccountMenu(viewModel: accountMenu, onOpenSettings: onOpenSettings)
            }
        }
        .aerieHull(compact: widthClass == .compact)
        .frame(minWidth: AerieMetric.mainWindowW, minHeight: AerieMetric.mainWindowH)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if windowWidth == nil { applyWidth(width) }
        }
        .background(WindowWidthReader { width in
            windowWidth = width
            applyWidth(width)
        })
        .widthClass(widthClass, bucket: widthBucket)
        .aerieWindowChrome()
    }

    private func applyWidth(_ width: CGFloat) {
        let newClass = WidthClass.forWidth(width)
        if newClass != widthClass { widthClass = newClass }
        let bucket = Int((width / 8).rounded())
        if bucket != widthBucket { widthBucket = bucket }
    }

    @ViewBuilder
    private var titlebar: some View {
        switch widthClass {
        case .regular:
            Titlebar(title: "Aerie")
        case .medium:
            if let tabBar {
                Titlebar {
                    SegmentedToggle(selection: tabBar.selection, counts: tabBar.counts)
                }
            } else {
                Titlebar(title: "Aerie")
            }
        case .compact:
            Titlebar(title: "Aerie", markOnly: true)
        }
    }
}
