import SwiftUI

/// The small amber "refresh this list" button that sits in the page header,
/// just after the count. Mirrors `v2/app.jsx` `RefreshButton`: a 26×26 amber
/// ghost square whose icon spins while a refresh is in flight.
///
/// `action` is the real refresh (an immediate poll tick). The icon spins in
/// whole forward turns: when the refresh ends it finishes the current turn
/// forward and lands upright, never reversing back to the start. One full turn
/// always plays, so a cache-fast refresh still reads as "it did something".
struct RefreshButton: View {
    /// The refresh to run on tap. Defaults to a no-op so snapshot tests and
    /// previews can render the button without wiring a real sync.
    var action: () async -> Void = {}

    /// Accumulating rotation in degrees. Only ever increases (each turn adds
    /// +360), so the icon never spins backward.
    @State private var rotation = 0.0
    /// True while a refresh's `action` is in flight. Read at each turn's
    /// completion to decide whether to keep spinning.
    @State private var isWorking = false
    /// True while the spin loop is running, so a re-press doesn't start a second
    /// overlapping loop.
    @State private var isAnimating = false

    var body: some View {
        Button(action: tapped) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AerieColor.amber)
                .rotationEffect(.degrees(rotation))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AerieColor.amber.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AerieColor.amber.opacity(0.30), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ⌘R refreshes the current tab's list. Only the active tab's screen —
        // and thus a single RefreshButton — is mounted at a time, so this
        // shortcut routes to the active tab's `action` automatically and reuses
        // the spin animation. The PR code-review screen mounts no RefreshButton,
        // so ⌘R is inert there.
        .keyboardShortcut("r", modifiers: .command)
        .help("Refresh list (⌘R)")
        .accessibilityLabel("Refresh list")
    }

    private func tapped() {
        guard !isWorking else { return }
        isWorking = true
        // Start the spin loop only if one isn't already running. A re-press
        // during the tail of the previous turn just re-arms `isWorking`; the
        // in-flight loop picks it up at its next completion.
        if !isAnimating {
            isAnimating = true
            spinForwardOneTurn()
        }
        Task {
            await action()
            isWorking = false
        }
    }

    /// Animates one full +360 turn, then decides — only once the turn has
    /// finished — whether to keep going. Because the stop decision happens at a
    /// turn boundary, the icon always lands upright and finishes forward instead
    /// of snapping back when the refresh ends.
    ///
    /// The re-arm hops to the next run-loop turn instead of recursing
    /// synchronously. When an animation completes *immediately* (logically
    /// complete — e.g. the refresh is tapped mid view-transition right after
    /// leaving the review screen, so the change has nothing to animate), the
    /// completion fires inside the same run-loop observer pass that dispatched
    /// it; recursing there starts another instantly-completing animation whose
    /// completion joins the same pass — an unbounded loop that pins the main
    /// thread, and the `Task` that clears `isWorking` never gets to run, so it
    /// can't terminate (captured live in a `sample` of the hang). Going through
    /// `Task { @MainActor … }` lets the run loop advance between turns, so the
    /// stop flag actually flips and the loop always ends.
    private func spinForwardOneTurn() {
        withAnimation(.linear(duration: 0.8)) {
            rotation += 360
        } completion: {
            Task { @MainActor in
                if isWorking {
                    spinForwardOneTurn()
                } else {
                    isAnimating = false
                }
            }
        }
    }
}
