import SwiftUI

/// First-run-after-setup popup. Asks the user to let Aerie write its entry
/// into `~/.claude/.mcp.json` so Claude Code can auto-discover the local MCP
/// server. Wraps `DialogShell` with the warning tone (amber ring + amber
/// "Allow" button) and shows a JSON-diff preview of what will be added.
///
/// Wiring into `AerieApp.AppRoot` (showing the dialog when bootstrap is `.ok`
/// AND `mcp.consent_decision == "unset"`) is intentionally left for a
/// follow-up task — this file delivers the view + a snapshot.
struct MCPConsentDialog: View {
    var onAllow: () async -> Void
    var onDecline: () -> Void

    var body: some View {
        DialogShell(
            tone: .warning,
            title: "Let Claude Code talk to Aerie?",
            subtitle: "Aerie can expose your tracked repos and PRs to Claude Code via a local MCP server.",
            primaryTitle: "Allow",
            onPrimary: { Task { await onAllow() } },
            secondaryTitle: "Not now",
            onSecondary: onDecline
        ) {
            VStack(alignment: .leading, spacing: 16) {
                hero
                description
                jsonDiffPreview
                footnotes
            }
        }
    }

    // MARK: - Sections

    private var hero: some View {
        HStack(spacing: 24) {
            iconCircle(systemImage: "sparkle", tint: AerieColor.amber)
            Image(systemName: "arrow.left.and.right")
                .foregroundStyle(AerieColor.text3)
            iconCircle(systemImage: "antenna.radiowaves.left.and.right", tint: AerieColor.ok)
        }
        .frame(maxWidth: .infinity)
    }

    private func iconCircle(systemImage: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .overlay(Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1))
                .frame(width: 56, height: 56)
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundStyle(tint)
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("If you allow this, Aerie will:")
                .font(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
            Text("• Add a local entry to ~/.claude/.mcp.json")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
            Text("• Keep the server bound to 127.0.0.1 with a rotating bearer token")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
        }
    }

    /// A pretty-printed diff of the JSON we'd add. Lines that begin with `+`
    /// render in the success-green tint; the rest stay in the neutral muted
    /// glass-text color.
    private var jsonDiffPreview: some View {
        let lines: [(String, Bool)] = [
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
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.0)
                    .font(AerieFont.code(11))
                    .foregroundStyle(line.1 ? AerieColor.ok : AerieColor.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AerieColor.glass1)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            footnote("Localhost-only — no inbound exposure.")
            footnote("Bearer token rotates on every launch.")
            footnote("Disable anytime in Settings → MCP.")
        }
    }

    private func footnote(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AerieColor.ok)
                .font(.system(size: 11))
            Text(text)
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
        }
    }
}
