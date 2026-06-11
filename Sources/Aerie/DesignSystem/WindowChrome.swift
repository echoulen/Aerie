import SwiftUI
import AppKit

/// Tweaks the host `NSWindow` so SwiftUI content extends the full window
/// height under the native title bar. Without this, `.windowStyle(.hiddenTitleBar)`
/// still leaves ~28 pt of empty title-bar space above the content — which,
/// stacked above the custom `Titlebar`, made the macOS traffic light buttons
/// appear twice (native ones on top, the design system's redraw below).
///
/// After applying this modifier:
///   - the native traffic light buttons remain visible and sit atop the
///     `Backdrop`'s gradients,
///   - ONLY the title-bar band moves the window (background drag is off, so
///     in-content gestures like the repo-list reorder grip aren't swallowed),
///   - no extra space is reserved for the title bar.
struct AerieWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            Self.apply(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            Self.apply(to: window)
        }
    }

    private static func apply(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        // Background drag OFF: the window moves only via the title-bar band (the
        // native, transparent title bar at the top, under the custom `Titlebar`).
        // With it ON, AppKit claimed mouseDown over content as a window-move and
        // swallowed in-content gestures — e.g. the Repositories reorder grip.
        // Title-bar dragging still works: that band is a real (transparent)
        // title bar, so `mouseDownCanMoveWindow` is true there.
        window.isMovableByWindowBackground = false
        // Aerie is a dark-only design (every `AerieColor` token is white-on-dark).
        // Lock the window to dark so SwiftUI's system-rendered controls resolve
        // their colors against dark too — otherwise, in macOS Light mode, the
        // account `Menu` label in a repo row paints with the system `labelColor`
        // (black), which is invisible on the dark surface ("Jarvis-E" going dark).
        window.appearance = NSAppearance(named: .darkAqua)
        // Make the host window itself transparent so the `Backdrop`'s
        // behind-window blur can frost the desktop / other apps *through* the
        // window. Without this, AppKit paints an opaque window background and
        // no glass shows. The Backdrop still lays a dark tint over the glass,
        // so white-on-dark content stays legible.
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

extension View {
    /// Apply Aerie's titlebar treatment to the host window: transparent
    /// title bar, full-size content view, and window movement restricted to the
    /// title-bar band (no background drag).
    func aerieWindowChrome() -> some View {
        background(AerieWindowChrome())
    }
}
