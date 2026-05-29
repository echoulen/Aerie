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
///   - dragging the empty area of the window moves it,
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
        window.isMovableByWindowBackground = true
    }
}

extension View {
    /// Apply Aerie's titlebar treatment to the host window: transparent
    /// title bar, full-size content view, draggable background.
    func aerieWindowChrome() -> some View {
        background(AerieWindowChrome())
    }
}
