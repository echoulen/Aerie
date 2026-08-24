import SwiftUI

/// Titlebar affordance for "a newer Aerie is out". Renders nothing at all when
/// there's no news (`.idle`) — the titlebar's default state is empty, so an
/// always-present update control would be permanent chrome for a rare event.
///
/// Visual language: the amber capsule from `AboutScreen`'s GitHub link, sized
/// to sit alongside the account pill on the other end of the titlebar.
struct UpdatePill: View {
    let phase: UpdatePhase
    /// Asks the shell to confirm + start the install (the confirmation is an
    /// AppKit alert, so it lives in `MainShell`, not here).
    var onInstall: () -> Void = {}
    /// Asks the shell to show the failure message behind a `.failed` pill.
    var onShowFailure: () -> Void = {}

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
                    Text(label)
                        .aerieFont(AerieFont.custom(.sans, size: 12).weight(.medium))
                }
                .foregroundStyle(isFailure ? AerieColor.err : AerieColor.amber)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isFailure ? AerieColor.dangerFill : AerieColor.amberSoft))
                .overlay(Capsule().strokeBorder(
                    isFailure ? AerieColor.dangerLine : AerieColor.amberLine, lineWidth: 1))
                .contentShape(Capsule())
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
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle").font(.system(size: 10, weight: .semibold))
        default:
            Image(systemName: "arrow.down.circle").font(.system(size: 11, weight: .semibold))
        }
    }

    private var isFailure: Bool { if case .failed = phase { return true }; return false }

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
