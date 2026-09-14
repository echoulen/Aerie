import SwiftUI

/// Titlebar affordance for "a newer Aerie is out". Renders nothing at all when
/// there's no news (`.idle`) — the titlebar's default state is empty, so an
/// always-present update control would be permanent chrome for a rare event.
///
/// Visual language: a small MARK III bevelled key (`HudKeyShape`) with an
/// uppercase tracked label, sized to sit alongside the account button on the
/// other end of the titlebar. Tones follow the state: gold when an update is
/// available (hover lifts the fill and glow), arc cyan with a spinner while
/// installing (a running process), crimson when the install failed.
struct UpdatePill: View {
    let phase: UpdatePhase
    /// Asks the shell to confirm + start the install (the confirmation is an
    /// AppKit alert, so it lives in `MainShell`, not here).
    var onInstall: () -> Void = {}
    /// Asks the shell to show the failure message behind a `.failed` pill.
    var onShowFailure: () -> Void = {}

    @State private var hovering = false

    private static let shape = HudKeyShape(cut: 6)

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
                        .tracking(1.1)
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Self.shape.fill(fill))
                .overlay(Self.shape.strokeBorder(border, lineWidth: 1))
                .shadow(color: glow, radius: glow == .clear ? 0 : 8)
                .contentShape(Self.shape)
            }
            .buttonStyle(.plain)
            .disabled(phase == .installing)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .help(helpText)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .installing:
            CardArcSpinner(size: 11)
        case .failed:
            Image(systemName: "exclamationmark.triangle").font(.system(size: 10, weight: .semibold))
        default:
            Image(systemName: "arrow.down.circle").font(.system(size: 11, weight: .semibold))
        }
    }

    private var isFailure: Bool { if case .failed = phase { return true }; return false }
    private var isInstalling: Bool { phase == .installing }

    private var foreground: Color {
        if isFailure { return AerieColor.dangerText }
        if isInstalling { return AerieColor.arc }
        return AerieColor.amber
    }

    private var fill: Color {
        if isFailure { return hovering ? AerieColor.dangerFillHover : AerieColor.dangerFill }
        if isInstalling { return AerieColor.arcSoft }
        return hovering ? AerieColor.amber.opacity(0.22) : AerieColor.amberSoft
    }

    private var border: Color {
        if isFailure { return hovering ? AerieColor.crimsonHot : AerieColor.dangerLine }
        if isInstalling { return AerieColor.arcLine }
        return hovering ? AerieColor.amber : AerieColor.amberLine
    }

    private var glow: Color {
        if isFailure { return hovering ? AerieColor.crimson.opacity(0.45) : .clear }
        if isInstalling { return AerieColor.arcGlow.opacity(0.35) }
        return AerieColor.amberGlow.opacity(hovering ? 0.5 : 0.3)
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
