import SwiftUI
import AppKit

/// The window's close / minimize / zoom lights, drawn by the `Titlebar` in
/// place of the native ones. The native buttons are pinned by AppKit at the
/// window's top-left edge, crowding the hull's bevel; drawing our own lets them
/// sit inset in the titlebar band like the MARK III design (and vision-claude's
/// `ArmorWindowLights`). Attaching this view hides its host window's native
/// buttons — windows without a `Titlebar` (first run) keep theirs.
///
/// Colors come from docs/superpowers/design/v2/styles.css:
///   `.r` #ff5f57, `.y` #febc2e, `.g` #28c840
/// Degrades gracefully when no window is attached (e.g. inside a snapshot host view).
struct TrafficLights: View {
    var compact: Bool = false
    @State private var hostWindow: NSWindow?

    private static let red    = Color(red: 0xff/255.0, green: 0x5f/255.0, blue: 0x57/255.0)
    private static let yellow = Color(red: 0xfe/255.0, green: 0xbc/255.0, blue: 0x2e/255.0)
    private static let green  = Color(red: 0x28/255.0, green: 0xc8/255.0, blue: 0x40/255.0)

    var body: some View {
        HStack(spacing: compact ? 7 : 8) {
            trafficButton(color: Self.red, help: "Close")        { hostWindow?.performClose(nil) }
            trafficButton(color: Self.yellow, help: "Minimize")  { hostWindow?.miniaturize(nil) }
            trafficButton(color: Self.green, help: "Full Screen") { hostWindow?.toggleFullScreen(nil) }
        }
        .background(WindowAccessor { window in
            hostWindow = window
            // Re-applied on every update: AppKit can re-show the buttons when
            // SwiftUI touches the title bar / style mask.
            for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window?.standardWindowButton(kind)?.isHidden = true
            }
        })
    }

    private func trafficButton(color: Color, help: String, action: @escaping () -> Void) -> some View {
        let size: CGFloat = compact ? 10 : 11
        return Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color, radius: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Captures the hosting `NSWindow` once the view is attached to the window
/// hierarchy. Calls `callback(nil)` if the view detaches.
private struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            callback(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            callback(nsView?.window)
        }
    }
}
