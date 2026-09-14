import SwiftUI

/// Settings → MCP main content.
///
/// Visual contract: `src/v2/mcp.jsx` (`SettingsMCP`):
///   1. Header — "Local MCP server", mono running/stopped subtitle, ghost sm
///      "Rotate token now".
///   2. Status card — green dot + "Server running" + mono uptime/pid, then a
///      130 / 1fr / auto key-value grid: endpoint, bearer token (eye toggle +
///      Copy), discovery file (Reveal).
///   3. CLAUDE CODE INTEGRATION — auto-register row with the pill toggle and,
///      when registered, a green status strip.
///   4. RECENT ACTIVITY — a table card (time / agent / tool / target / result);
///      clicking a row → `onViewActivity`.
struct MCPSettingsScreen: View {
    @Bindable var viewModel: MCPSettingsViewModel
    var onViewActivity: (MCPActivityRecord) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsPageHeader(
                    eyebrow: "MCP",
                    title: "Local MCP server",
                    subtitle: viewModel.status.running ? "running" : "stopped"
                ) {
                    Button("Rotate token now") {
                        Task { await viewModel.rotateNow() }
                    }
                    .buttonStyle(.hud(.ghost, size: .small))
                }

                serverStatusCard.padding(.top, 18)

                SectionEyebrow(text: "Claude Code integration").padding(.top, 28)
                integrationCard.padding(.top, 10)

                SectionEyebrow(text: "Recent activity").padding(.top, 28)
                activityCard.padding(.top, 10)
            }
            .settingsPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Server status

    private var serverStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                SettingsDot(tone: viewModel.status.running ? .ok : .muted)
                Text(viewModel.status.running ? "Server running" : "Server stopped")
                    .aerieFont(AerieFont.body())
                    .foregroundStyle(AerieColor.text1)
                Spacer()
                if let uptime = viewModel.uptimeLabel {
                    Text("uptime \(uptime) · pid \(viewModel.status.pid)")
                        .aerieFont(AerieFont.code(11))
                        .foregroundStyle(AerieColor.text4)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                kvRow(label: "endpoint", value: viewModel.status.endpoint?.absoluteString ?? "—") {
                    ghostButton("Copy") { viewModel.copyEndpoint() }
                }
                kvRow(label: "bearer token", value: viewModel.displayedToken.isEmpty ? "—" : viewModel.displayedToken,
                      leading: {
                          Button {
                              if viewModel.tokenRevealed { viewModel.hideToken() } else { viewModel.revealToken() }
                          } label: {
                              Image(systemName: viewModel.tokenRevealed ? "eye.slash" : "eye")
                                  .font(.system(size: 11))
                                  .padding(.horizontal, -4)
                                  .padding(.vertical, -2)
                          }
                          .buttonStyle(.hud(.ghost, size: .small))
                          .accessibilityLabel(viewModel.tokenRevealed ? "Hide" : "Reveal")
                      }) {
                    ghostButton("Copy") { viewModel.copyToken() }
                }
                kvRow(label: "discovery file", value: viewModel.discoveryFilePath.path, valueColor: AerieColor.text2) {
                    ghostButton("Reveal") { viewModel.revealDiscoveryFileInFinder() }
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    // MARK: - Integration

    private var integrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    (Text("Auto-register in ")
                        + Text("~/.claude/.mcp.json").font(AerieFont.code(13).resolve(scale: fontScale)))
                        .aerieFont(AerieFont.custom(.sans, size: 14))
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
                .toggleStyle(.aerie)
            }
            if viewModel.autoRegisterOn {
                HStack(spacing: 10) {
                    SettingsDot(tone: .ok)
                    (Text("aerie").foregroundStyle(AerieColor.text1)
                        + Text(" entry registered").foregroundStyle(AerieColor.text2))
                        .aerieFont(AerieFont.custom(.sans, size: 12.5))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                        .fill(AerieColor.ok.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                        .strokeBorder(AerieColor.ok.opacity(0.30), lineWidth: 1)
                )
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    @Environment(\.interfaceFontScale) private var fontScale

    // MARK: - Activity

    private var activityCard: some View {
        VStack(spacing: 0) {
            activityHeader
            if viewModel.recentActivity.isEmpty {
                Text("No MCP calls yet.")
                    .aerieFont(AerieFont.small())
                    .foregroundStyle(AerieColor.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
            } else {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    private var activityHeader: some View {
        HStack(spacing: 12) {
            Text("time").frame(width: 90, alignment: .leading)
            Text("agent").frame(width: 150, alignment: .leading)
            Text("tool").frame(maxWidth: .infinity, alignment: .leading)
            Text("target").frame(maxWidth: .infinity, alignment: .leading)
            Text("result").frame(width: 60, alignment: .trailing)
        }
        .textCase(.uppercase)
        .aerieFont(AerieFont.code(10))
        .tracking(1.2)                                   // 0.12em @ 10pt
        .foregroundStyle(AerieColor.text4)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AerieColor.glassLine).frame(height: 1)
        }
    }

    private func activityRow(_ record: MCPActivityRecord) -> some View {
        Button {
            onViewActivity(record)
        } label: {
            HStack(spacing: 12) {
                Text(relativeTime(record.at))
                    .foregroundStyle(AerieColor.text3)
                    .frame(width: 90, alignment: .leading)
                Text(record.agentId ?? "—")
                    .foregroundStyle(AerieColor.text2)
                    .frame(width: 150, alignment: .leading)
                Text(record.tool)
                    .foregroundStyle(AerieColor.text1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(record.target ?? "—")
                    .foregroundStyle(AerieColor.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(record.ok ? "✓" : "✕")
                    .foregroundStyle(record.ok ? AerieColor.ok : AerieColor.err)
                    .frame(width: 60, alignment: .trailing)
                    .accessibilityLabel(record.ok ? "succeeded" : "failed")
            }
            .aerieFont(AerieFont.code(12))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
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

    /// A row of the status card's 130 / 1fr / auto key-value grid: mono 11
    /// text-4 key, mono 12.5 value, optional inline control after the value,
    /// and trailing ghost sm action(s).
    private func kvRow<Leading: View, Trailing: View>(
        label: String,
        value: String,
        valueColor: Color = AerieColor.text1,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .aerieFont(AerieFont.code(11))
                .tracking(0.22)                          // 0.02em @ 11pt
                .foregroundStyle(AerieColor.text4)
                .frame(width: 130, alignment: .leading)
            HStack(spacing: 8) {
                Text(value)
                    .aerieFont(AerieFont.code(12.5))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                leading()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.hud(.ghost, size: .small))
    }
}
