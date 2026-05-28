import SwiftUI
import AppKit

/// macOS-style traffic light buttons (close / minimize / zoom).
/// Colors come from docs/superpowers/design/v2/styles.css:
///   `.r` #ff5f57, `.y` #febc2e, `.g` #28c840
/// Clicking each circle invokes the corresponding action on the host `NSWindow`.
/// Degrades gracefully when no window is attached (e.g. inside a snapshot host view).
struct TrafficLights: View {
    @State private var hostWindow: NSWindow?

    private static let red    = Color(red: 0xff/255.0, green: 0x5f/255.0, blue: 0x57/255.0)
    private static let yellow = Color(red: 0xfe/255.0, green: 0xbc/255.0, blue: 0x2e/255.0)
    private static let green  = Color(red: 0x28/255.0, green: 0xc8/255.0, blue: 0x40/255.0)

    var body: some View {
        HStack(spacing: 8) {
            trafficButton(color: Self.red)    { hostWindow?.performClose(nil) }
            trafficButton(color: Self.yellow) { hostWindow?.miniaturize(nil) }
            trafficButton(color: Self.green)  { hostWindow?.zoom(nil) }
        }
        .background(WindowAccessor { hostWindow = $0 })
    }

    private func trafficButton(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
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
