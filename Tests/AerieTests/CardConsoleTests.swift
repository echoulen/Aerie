import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

@MainActor
private final class ConsoleFeed: ObservableObject {
    @Published var lines: [String] = []
}

private struct StreamingConsoleHarness: View {
    @ObservedObject var feed: ConsoleFeed

    var body: some View {
        // Flat background: in a live window the Backdrop's starfield drifts,
        // which would make the image differ run to run.
        ZStack {
            AerieColor.space1
            CardConsole(lines: feed.lines, maxHeight: 150)
                .padding(20)
        }
    }
}

/// Regression coverage for the AI Review / Create PR console. Lines must be
/// appended while the console is on screen in a real window: rendering a fixed
/// array never reproduced the bug where a lazy stack left the well blank.
@MainActor
final class CardConsoleTests: XCTestCase {
    func test_console_rendersLinesStreamedWhileVisible() async throws {
        let feed = ConsoleFeed()
        let size = CGSize(width: 600, height: 240)
        let host = NSHostingView(rootView: StreamingConsoleHarness(feed: feed))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        for i in 0..<12 {
            feed.lines.append("› line \(i) reading SomeFile\(i).swift")
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 300_000_000)

        // The caret blinks, so allow a small pixel budget — a blank well (the
        // regression) differs by far more than the 7×12 caret.
        assertSnapshot(of: host, as: .image(precision: 0.99, size: size))
    }
}
