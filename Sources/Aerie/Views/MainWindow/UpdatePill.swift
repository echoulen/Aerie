import SwiftUI

/// Titlebar affordance for "a newer Aerie is out". Renders nothing at all when
/// there's no news (`.idle`) — the titlebar's default state is empty, so an
/// always-present update control would be permanent chrome for a rare event.
///
/// Visual language (`system.jsx`): a MARK III `.pill` (radius 2, 600 11pt
/// uppercase, 0.10em tracking, 6×12 padding) sized to sit alongside the account
/// button on the other end of the titlebar — `pill amber` "↓ Update to x" when
/// available, `pill arc` with an 11pt spinner while installing (a running
/// process), `pill err` "▲ Update failed" when the install failed.
struct UpdatePill: View {
    let phase: UpdatePhase
    /// Asks the shell to confirm + start the install (the confirmation is an
    /// AppKit alert, so it lives in `MainShell`, not here).
    var onInstall: () -> Void = {}
    /// Asks the shell to show the failure message behind a `.failed` pill.
    var onShowFailure: () -> Void = {}

    private static let shape = RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)

    /// The pill's text, or nil when the pill shouldn't render. Pure + static so
    /// the copy is testable without building a view hierarchy.
    static func label(for phase: UpdatePhase) -> String? {
        switch phase {
        case .idle: return nil
        case .available(_, let latest): return "Update to \(latest)"
        case .installing: return "Updating…"
        case .failed: return "Update failed"
        }
    }

    var body: some View {
        if let label = Self.label(for: phase) {
            Button(action: tapped) {
                HStack(spacing: 6) {
                    icon
                    Text(label.uppercased())
                        .aerieFont(AerieFont.custom(.sans, size: 11).weight(.semibold))
                        .tracking(1.1) // 0.10em @ 11px
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Self.shape.fill(fill))
                .overlay(Self.shape.strokeBorder(border, lineWidth: 1))
                // `.pill.amber` / `.pill.arc`: `0 0 16px -8px <glow>`.
                .shadow(color: glow, radius: glow == .clear ? 0 : 6)
                .contentShape(Self.shape)
            }
            .buttonStyle(.plain)
            .disabled(phase == .installing)
            .help(helpText)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .installing:
            CardArcSpinner(size: 11)
        case .failed:
            Text("▲").aerieFont(AerieFont.custom(.sans, size: 9))
        default:
            Text("↓").aerieFont(AerieFont.custom(.sans, size: 11).weight(.semibold))
        }
    }

    private var isFailure: Bool { if case .failed = phase { return true }; return false }
    private var isInstalling: Bool { phase == .installing }

    private var foreground: Color {
        if isFailure { return AerieColor.crimsonHot }
        if isInstalling { return AerieColor.arc }
        return AerieColor.amber
    }

    private var fill: Color {
        if isFailure { return AerieColor.crimsonSoft }
        if isInstalling { return AerieColor.arcSoft }
        return AerieColor.amberSoft
    }

    private var border: Color {
        if isFailure { return AerieColor.crimsonLine }
        if isInstalling { return AerieColor.arcLine }
        return AerieColor.amberLine
    }

    private var glow: Color {
        if isFailure { return .clear }
        if isInstalling { return AerieColor.arcGlow.opacity(0.35) }
        return AerieColor.amberGlow.opacity(0.35)
    }

    private var helpText: String {
        switch phase {
        case .available(let current, let latest):
            return "Install Aerie \(latest) (you have \(current)) — Aerie will quit and relaunch"
        case .installing: return "Installing the update — Aerie will relaunch itself"
        case .failed: return "The update failed. Click for details."
        case .idle: return ""
        }
    }

    private func tapped() {
        switch phase {
        case .available: onInstall()
        case .failed: onShowFailure()
        case .installing, .idle: break
        }
    }
}
