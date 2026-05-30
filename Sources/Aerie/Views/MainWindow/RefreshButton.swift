import SwiftUI

/// The small amber "refresh this list" button that sits in the page header,
/// just after the count. Mirrors `v2/app.jsx` `RefreshButton`: a 26×26 amber
/// ghost square whose icon spins while a refresh is in flight.
///
/// `action` is the real refresh (an immediate poll tick). The icon keeps
/// spinning until it returns, with a short minimum so a cache-fast refresh
/// still reads as "it did something".
struct RefreshButton: View {
    /// The refresh to run on tap. Defaults to a no-op so snapshot tests and
    /// previews can render the button without wiring a real sync.
    var action: () async -> Void = {}

    @State private var isSpinning = false

    var body: some View {
        Button(action: tapped) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AerieColor.amber)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .default,
                    value: isSpinning
                )
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
        .help("Refresh list")
        .accessibilityLabel("Refresh list")
    }

    private func tapped() {
        guard !isSpinning else { return }
        Task {
            isSpinning = true
            async let work: Void = action()
            // Keep one full rotation visible even when the refresh is instant.
            try? await Task.sleep(nanoseconds: 700_000_000)
            await work
            isSpinning = false
        }
    }
}
