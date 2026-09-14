import SwiftUI
import AppKit

/// Shared layout for the first-run panels (`v2/first-run.jsx`): a 54pt icon
/// tile, a 32pt title, prose, a `$ command` box with a Copy key, optional extra
/// content, and an action row (gold primary + ghost Quit Aerie + the amber
/// "checking every 5s" indicator). No card — the body sits directly on the
/// warm-washed backdrop.
struct FirstRunPanel<ExtraBody: View>: View {
    let icon: String
    let title: String
    let prose: String
    let command: String
    let primaryButtonTitle: String
    var onPrimary: () -> Void
    var onQuit: () -> Void = { NSApplication.shared.terminate(nil) }
    /// Gap between the command box and the action row (32; 28 when `extra`
    /// carries a tip block).
    var actionsSpacing: CGFloat = 32
    @ViewBuilder var extra: () -> ExtraBody

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iconTile
            Text(title)
                .aerieFont(AerieFont.custom(.sans, size: 32).weight(.medium))
                .foregroundStyle(AerieColor.text1)
                .lineSpacing(1)
                .padding(.top, 24)
            Text(prose)
                .aerieFont(AerieFont.custom(.sans, size: 14.5))
                .foregroundStyle(AerieColor.text2)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.top, 14)
            commandBlock
                .padding(.top, 24)
            extra()
            actionRow
                .padding(.top, actionsSpacing)
        }
        .frame(width: 640, alignment: .leading)
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: AerieMetric.radiusCard, style: .continuous)
            .fill(AerieColor.glass2)
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusCard, style: .continuous)
                    .strokeBorder(AerieColor.glassLine2, lineWidth: 1)
            )
            .frame(width: 54, height: 54)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AerieColor.amber)
            )
    }

    private var commandBlock: some View {
        HStack(spacing: 10) {
            Text("$")
                .aerieFont(AerieFont.code(13.5))
                .foregroundStyle(AerieColor.text4)
            Text(command)
                .aerieFont(AerieFont.code(13.5))
                .foregroundStyle(AerieColor.text1)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            .buttonStyle(.hud(.standard, size: .small))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .dialogInset(fill: Color.black.opacity(0.32), border: AerieColor.glassLine2)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(primaryButtonTitle, action: onPrimary)
                .buttonStyle(.hud(.amber))
            Button("Quit Aerie", action: onQuit)
                .buttonStyle(.hud(.ghost))
            Spacer()
            checkingIndicator
        }
    }

    private var checkingIndicator: some View {
        HStack(spacing: 8) {
            Text("checking every 5s")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
            Circle().fill(AerieColor.amber)
                .frame(width: 7, height: 7)
                .shadow(color: AerieColor.amberGlow, radius: 5)
        }
    }
}

/// Convenience initializer for panels without extra body content.
extension FirstRunPanel where ExtraBody == EmptyView {
    init(
        icon: String,
        title: String,
        prose: String,
        command: String,
        primaryButtonTitle: String,
        onPrimary: @escaping () -> Void,
        onQuit: @escaping () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.icon = icon
        self.title = title
        self.prose = prose
        self.command = command
        self.primaryButtonTitle = primaryButtonTitle
        self.onPrimary = onPrimary
        self.onQuit = onQuit
        self.extra = { EmptyView() }
    }
}

/// First-run body shown when the `gh` CLI is not installed.
struct NoGhBody: View {
    var onRecheck: () -> Void
    var body: some View {
        FirstRunPanel(
            icon: "terminal",
            title: "Install GitHub CLI",
            prose: "Aerie reads your existing gh credentials. Install gh first — Aerie never asks for your tokens directly.",
            command: "brew install gh",
            primaryButtonTitle: "I've installed it — re-check",
            onPrimary: onRecheck
        )
    }
}
