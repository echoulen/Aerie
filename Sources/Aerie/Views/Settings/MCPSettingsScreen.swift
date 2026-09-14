import SwiftUI

/// Settings → MCP main content.
///
/// Three cards stacked vertically:
///   1. Server status (running dot + pid + uptime + endpoint + token + rotate)
///   2. Claude Code integration (auto-register toggle + discovery file row)
///   3. Recent activity (last 6 MCP calls, click → ViewRequestModal)
///
/// Design ref: docs/superpowers/design/v2/mcp.jsx · `MCPSettingsBody`.
///
/// MARK III: a `SettingsPageHeader`, each card hung off a mono section label,
/// bevelled HUD keys, and a HUD switch. Arc cyan is used only for the live
/// "running" status (reactor ring, section-label pulse); a stopped server
/// reads muted, a failed call reads crimson, a successful one green.
struct MCPSettingsScreen: View {
    @Bindable var viewModel: MCPSettingsViewModel
    var onViewActivity: (MCPActivityRecord) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(
                    eyebrow: "MCP",
                    title: "Local MCP server",
                    subtitle: "Claude Code ↔ Aerie"
                )
                serverStatusCard
                integrationCard
                activityCard
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Server status

    private var serverStatusCard: some View {
        sectionCard(title: "Server", live: viewModel.status.running) {
            VStack(alignment: .leading, spacing: 16) {
                statusHeader
                kvRow(
                    label: "endpoint",
                    value: viewModel.status.endpoint?.absoluteString ?? "—",
                    trailingButton: ("Copy", { viewModel.copyEndpoint() })
                )
                kvRow(
                    label: "bearer token",
                    value: viewModel.displayedToken.isEmpty ? "—" : viewModel.displayedToken,
                    leadingTrailingButtons: [
                        (viewModel.tokenRevealed ? "Hide" : "Reveal", {
                            if viewModel.tokenRevealed { viewModel.hideToken() } else { viewModel.revealToken() }
                        }),
                        ("Copy", { viewModel.copyToken() }),
                    ]
                )
                rotateRow
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            if viewModel.status.running {
                // Running = live energy → arc cyan.
                ArcRing(size: 20)
            } else {
                Circle()
                    .fill(AerieColor.text4)
                    .frame(width: 8, height: 8)
            }
            Text(viewModel.status.running ? "Server running" : "Server stopped")
                .aerieFont(AerieFont.body().weight(.medium))
                .foregroundStyle(AerieColor.text1)
            Spacer()
            if let uptime = viewModel.uptimeLabel {
                HudNote(text: "uptime \(uptime) · pid \(viewModel.status.pid)")
            }
        }
    }

    private var rotateRow: some View {
        HStack {
            Spacer()
            Button("Rotate token now") {
                Task { await viewModel.rotateNow() }
            }
            .buttonStyle(.hud(.standard, size: .small))
        }
    }

    // MARK: - Integration

    private var integrationCard: some View {
        sectionCard(title: "Claude Code integration") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-register in ~/.claude/.mcp.json")
                            .aerieFont(AerieFont.body())
                            .foregroundStyle(AerieColor.text1)
                        Text("Every Claude Code session on this machine can discover Aerie automatically.")
                            .aerieFont(AerieFont.small())
                            .foregroundStyle(AerieColor.text3)
                    }
                    Spacer()
                    Toggle("Auto-register in ~/.claude/.mcp.json", isOn: Binding(
                        get: { viewModel.autoRegisterOn },
                        set: { v in Task { await viewModel.setAutoRegister(v) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.hud)
                }
                kvRow(
                    label: "discovery file",
                    value: viewModel.discoveryFilePath.path,
                    trailingButton: ("Reveal", { viewModel.revealDiscoveryFileInFinder() })
                )
            }
        }
    }

    // MARK: - Activity

    private var activityCard: some View {
        sectionCard(title: "Recent activity") {
            if viewModel.recentActivity.isEmpty {
                Text("No MCP calls yet.")
                    .aerieFont(AerieFont.small())
                    .foregroundStyle(AerieColor.text3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.recentActivity.enumerated()), id: \.element.id) { idx, record in
                        if idx > 0 {
                            Rectangle()
                                .fill(AerieColor.glassLine)
                                .frame(height: 1)
                        }
                        activityRow(record)
                    }
                }
            }
        }
    }

    private func activityRow(_ record: MCPActivityRecord) -> some View {
        Button {
            onViewActivity(record)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: record.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(record.ok ? AerieColor.ok : AerieColor.crimsonHot)
                    .shadow(color: (record.ok ? AerieColor.ok : AerieColor.crimson).opacity(0.5), radius: 4)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.tool)
                        .aerieFont(AerieFont.code(12).weight(.medium))
                        .foregroundStyle(AerieColor.text1)
                    if let target = record.target {
                        Text(target)
                            .aerieFont(AerieFont.small())
                            .foregroundStyle(AerieColor.text3)
                    }
                }
                Spacer()
                Text(relativeTime(record.at).uppercased())
                    .aerieFont(AerieFont.code(10.5))
                    .tracking(1.0)
                    .foregroundStyle(AerieColor.text3)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date) -> String {
        let elapsed = -date.timeIntervalSinceNow
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: - Building blocks

    /// Key / value row used by both server-status and integration cards.
    /// Supports either a single trailing button or a row of trailing buttons
    /// (used by the bearer-token row for Reveal + Copy).
    private func kvRow(
        label: String,
        value: String,
        trailingButton: (String, () -> Void)? = nil,
        leadingTrailingButtons: [(String, () -> Void)] = []
    ) -> some View {
        HStack(spacing: 14) {
            Text(label.uppercased())
                .aerieFont(AerieFont.eyebrow())
                .tracking(1.6)
                .foregroundStyle(AerieColor.text3)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(AerieColor.text1)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .hudWell()
            ForEach(Array(leadingTrailingButtons.enumerated()), id: \.offset) { _, pair in
                ghostButton(pair.0, action: pair.1)
            }
            if let pair = trailingButton {
                ghostButton(pair.0, action: pair.1)
            }
        }
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.hud(.standard, size: .small))
    }

    @ViewBuilder
    private func sectionCard<Body: View>(
        title: String,
        live: Bool = false,
        @ViewBuilder content: () -> Body
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: title, live: live)
            content()
                .padding(AerieMetric.cardPaddingV)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(.card)
        }
    }
}
