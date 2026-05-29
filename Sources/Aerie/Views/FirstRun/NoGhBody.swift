import SwiftUI
import AppKit

/// Shared layout for the first-run panels: title, prose, command block with
/// Copy, optional extra content, and an action row (primary button +
/// Quit Aerie + "checking every 5s" indicator).
struct FirstRunPanel<ExtraBody: View>: View {
    let title: String
    let prose: String
    let command: String
    let primaryButtonTitle: String
    var onPrimary: () -> Void
    var onQuit: () -> Void = { NSApplication.shared.terminate(nil) }
    @ViewBuilder var extra: () -> ExtraBody

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(AerieColor.text1)
            Text(prose)
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
                .lineSpacing(3)
            commandBlock
            extra()
            actionRow
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var commandBlock: some View {
        HStack {
            Text(command)
                .aerieFont(AerieFont.code())
                .foregroundStyle(AerieColor.text2)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AerieColor.glass1)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                )
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Text("Copy")
                    .aerieFont(AerieFont.small().weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(AerieColor.text2)
                    .background(Capsule().fill(AerieColor.glass2))
                    .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onPrimary) {
                Text(primaryButtonTitle)
                    .aerieFont(AerieFont.small().weight(.medium))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .foregroundStyle(AerieColor.amber)
                    .background(Capsule().fill(AerieColor.amberSoft))
                    .overlay(Capsule().strokeBorder(AerieColor.amberLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: onQuit) {
                Text("Quit Aerie")
                    .aerieFont(AerieFont.small())
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(AerieColor.text3)
            }
            .buttonStyle(.plain)
            Spacer()
            checkingIndicator
        }
    }

    private var checkingIndicator: some View {
        HStack(spacing: 8) {
            Circle().fill(AerieColor.amber)
                .frame(width: 6, height: 6)
                .shadow(color: AerieColor.amberGlow, radius: 3)
            Text("checking every 5s")
                .aerieFont(AerieFont.eyebrow())
                .foregroundStyle(AerieColor.text3)
        }
    }
}

/// Convenience initializer for panels without extra body content.
extension FirstRunPanel where ExtraBody == EmptyView {
    init(
        title: String,
        prose: String,
        command: String,
        primaryButtonTitle: String,
        onPrimary: @escaping () -> Void,
        onQuit: @escaping () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
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
            title: "Install GitHub CLI",
            prose: "Aerie reads your existing gh credentials. Install gh first — Aerie never asks for your tokens directly.",
            command: "brew install gh",
            primaryButtonTitle: "I've installed it — re-check",
            onPrimary: onRecheck
        )
    }
}
