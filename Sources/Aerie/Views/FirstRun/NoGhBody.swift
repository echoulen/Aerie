import SwiftUI
import AppKit

/// Shared layout for the first-run panels: gold eyebrow + title, prose, a
/// console command block with Copy, optional extra content, and an action row
/// (gold primary CTA + ghost Quit Aerie + the arc-cyan "checking every 5s"
/// polling tick — the one live-energy element on the screen).
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
            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow(text: "First run")
                Text(title)
                    .aerieFont(AerieFont.custom(.sans, size: 32).weight(.semibold))
                    .tracking(0.3)
                    .foregroundStyle(AerieColor.text1)
                HudRail(color: AerieColor.amberLine)
                    .frame(width: 180)
                    .padding(.top, 4)
            }
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
                .dialogInset()
                .overlay(alignment: .leading) {
                    // `.console` prompt strut — a gold hairline on the leading edge.
                    Rectangle().fill(AerieColor.amberLine).frame(width: 2)
                        .padding(.vertical, 1)
                        .allowsHitTesting(false)
                }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            .buttonStyle(.hud(.standard))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(primaryButtonTitle, action: onPrimary)
                .buttonStyle(.hud(.amber))
            Button("Quit Aerie", action: onQuit)
                .buttonStyle(.hud(.ghost))
            Spacer()
            checkingIndicator
        }
    }

    // Live polling tick — arc cyan is reserved for exactly this kind of energy.
    private var checkingIndicator: some View {
        HStack(spacing: 8) {
            PollingTick()
            Text("CHECKING EVERY 5S")
                .aerieFont(AerieFont.eyebrow())
                .tracking(1.8)
                .foregroundStyle(AerieColor.text3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("checking every 5s")
    }
}

/// A pulsing arc-cyan dot marking a live background poll.
private struct PollingTick: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(AerieColor.arc)
            .frame(width: 6, height: 6)
            .shadow(color: AerieColor.arcGlow, radius: pulsing ? 6 : 3)
            .opacity(pulsing ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulsing = true }
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
