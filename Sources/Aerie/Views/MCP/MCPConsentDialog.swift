import SwiftUI
import AppKit

/// First-run-after-setup popup. Asks the user to let Aerie write its entry
/// into `~/.claude/.mcp.json` so Claude Code can auto-discover the local MCP
/// server, showing a JSON-diff preview of what will be added.
///
/// Visual contract: `v2/mcp.jsx` consent dialog — its own 560pt card (not
/// `DialogShell`): gold ring, a Claude ↔ Aerie hero, a diff preview with a
/// Copy key, a dotted notes list, and a footer with a settings hint, a ghost
/// "Not now" and the gold `.btn.amber` "Allow".
struct MCPConsentDialog: View {
    var onAllow: () async -> Void
    var onDecline: () -> Void

    /// The block Aerie adds to `~/.claude/.mcp.json`; `true` marks added lines.
    private static let diffLines: [(String, Bool)] = [
        ("{", false),
        ("  \"mcpServers\": {", false),
        ("+   \"aerie\": {", true),
        ("+     \"type\": \"http\",", true),
        ("+     \"url\": \"http://127.0.0.1:<port>/mcp\",", true),
        ("+     \"headers\": {", true),
        ("+       \"Authorization\": \"Bearer <token>\"", true),
        ("+     }", true),
        ("+   }", true),
        ("  }", false),
        ("}", false),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            card
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private var card: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                Text("Let Claude Code talk to Aerie?")
                    .aerieFont(AerieFont.custom(.sans, size: 20).weight(.medium))
                    .foregroundStyle(AerieColor.text1)
                    .padding(.top, 18)
                Text("Aerie can expose your tracked repos and PRs to Claude Code via a local MCP server. If you allow this, Aerie will add a local entry to ~/.claude/.mcp.json.")
                    .aerieFont(AerieFont.custom(.sans, size: 13.5))
                    .foregroundStyle(AerieColor.text2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                jsonDiffPreview
                    .padding(.top, 16)
                notes
                    .padding(.top, 14)
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        .frame(width: 560)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                Color(red: 28/255, green: 26/255, blue: 32/255).opacity(0.82)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AerieMetric.radiusDialog, style: .continuous))
        .overlay(alignment: .top) {
            Rectangle().fill(AerieColor.glassHighlight).frame(height: 1)
                .padding(.horizontal, 1)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusDialog, style: .continuous)
                .strokeBorder(AerieColor.amberLine, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.7), radius: 30, y: 30)
    }

    // MARK: - Sections

    /// Claude tile — "—" — Aerie tile.
    private var hero: some View {
        HStack(spacing: 12) {
            claudeTile
            Text("—")
                .aerieFont(AerieFont.custom(.sans, size: 18))
                .foregroundStyle(AerieColor.text4)
            aerieTile
        }
    }

    // `radial-gradient(oklch(0.75 0.13 30), oklch(0.50 0.16 25))` with a white "C".
    private var claudeTile: some View {
        RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
            .fill(RadialGradient(
                colors: [Color(red: 0.93, green: 0.53, blue: 0.44), Color(red: 0.64, green: 0.20, blue: 0.18)],
                center: .center, startRadius: 0, endRadius: 27
            ))
            .frame(width: 38, height: 38)
            .overlay(
                Text("C")
                    .aerieFont(AerieFont.custom(.sans, size: 18).weight(.semibold))
                    .foregroundStyle(.white)
            )
    }

    // Gold tile with the brand orb and a gold glow.
    private var aerieTile: some View {
        RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
            .fill(AerieColor.amberSoft)
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(AerieColor.amberLine, lineWidth: 1)
            )
            .frame(width: 38, height: 38)
            .overlay(BrandMark(size: 16, pulses: false))
            .shadow(color: AerieColor.amberGlow.opacity(0.5), radius: 10)
    }

    /// Diff preview: a header row (path · diff + ghost Copy) over the JSON, with
    /// added lines in ok green and the rest in text-2.
    private var jsonDiffPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("~/.claude/.mcp.json · diff")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                Spacer(minLength: 8)
                Button("Copy") {
                    let added = Self.diffLines.filter(\.1).map { String($0.0.dropFirst()) }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(added.joined(separator: "\n"), forType: .string)
                }
                .buttonStyle(.hud(.ghost, size: .small))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.20))
            .overlay(alignment: .bottom) {
                Rectangle().fill(AerieColor.glassLine).frame(height: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(Self.diffLines.enumerated()), id: \.offset) { _, line in
                    Text(line.0)
                        .aerieFont(AerieFont.code(11.5))
                        .foregroundStyle(line.1 ? AerieColor.ok : AerieColor.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dialogInset(fill: Color.black.opacity(0.32))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            note("Localhost-only — bound to 127.0.0.1, no inbound exposure.")
            note("Bearer token rotates on every launch.")
            note("Disable anytime in Settings → MCP.")
        }
    }

    private func note(_ text: String) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(AerieColor.text4)
                .frame(width: 4, height: 4)
            Text(text)
                .aerieFont(AerieFont.custom(.sans, size: 12))
                .foregroundStyle(AerieColor.text3)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("You can change this later in Settings")
                .aerieFont(AerieFont.custom(.sans, size: 11.5))
                .foregroundStyle(AerieColor.text4)
            Spacer(minLength: 8)
            Button("Not now", action: onDecline)
                .buttonStyle(.hud(.ghost))
            Button("Allow") { Task { await onAllow() } }
                .buttonStyle(.hud(.amber))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .top) {
            Rectangle().fill(AerieColor.glassLine).frame(height: 1)
        }
    }
}
