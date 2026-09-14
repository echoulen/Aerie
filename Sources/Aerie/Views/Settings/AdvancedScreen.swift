import SwiftUI

/// Settings → Advanced main content.
///
/// Layout follows the v2 design (`advanced.jsx`):
///   ┌──────────────────────────────────────────────────────┐
///   │ ADVANCED                                             │  ← eyebrow
///   │ Polling & rate limits   how often Aerie refreshes    │  ← page title + sub
///   │                              [ Reset to defaults ]   │
///   │ POLLING CADENCE                                      │  ← section eyebrow
///   │  ┌ card: sliders + quota warning chip ┐              │
///   │ RATE LIMIT                                           │
///   │  ┌ card: per-account meters ┐                        │
///   │ BEHAVIOR                                             │
///   │  ┌ card: focus toggles (switch right-aligned) ┐      │
///   └──────────────────────────────────────────────────────┘
///
/// MARK III (`advanced.jsx`): `SettingsPageHeader` with a `.btn ghost sm`
/// reset, `.section-eyebrow` sub-sections (28 top, card 10 below), a 22/24
/// cadence card with gold-fill sliders and a flat warn strip, a 22/24 rate
/// limit card laid out as hairline-separated per-account columns, and a
/// behavior card of 16/20 rows with the design's pill toggle.
///
/// Setter bindings dispatch into `Task { await viewModel.set... }` so
/// SwiftUI's synchronous binding contract is preserved while the
/// underlying persistence + cadence-apply step runs async.
struct AdvancedScreen: View {
    @Bindable var viewModel: AdvancedViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                sectionEyebrow("POLLING CADENCE").padding(.top, 28)
                pollingCard.padding(.top, 10)

                sectionEyebrow("RATE LIMIT").padding(.top, 28)
                rateLimitCard.padding(.top, 10)

                sectionEyebrow("BEHAVIOR").padding(.top, 28)
                behaviorCard.padding(.top, 10)
            }
            .settingsPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        SettingsPageHeader(
            eyebrow: "Advanced",
            title: "Polling & rate limits",
            subtitle: "how often Aerie refreshes"
        ) {
            resetButton
        }
    }

    // MARK: - Polling

    private var pollingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 28) {
                CadenceSlider(
                    label: "Active repo",
                    seconds: Binding(
                        get: { viewModel.activeCadence },
                        set: { v in Task { await viewModel.setActiveCadence(v) } }
                    ),
                    range: 15...600
                )
                CadenceSlider(
                    label: "Background repos",
                    seconds: Binding(
                        get: { viewModel.backgroundCadence },
                        set: { v in Task { await viewModel.setBackgroundCadence(v) } }
                    ),
                    range: 60...3600
                )
                if viewModel.activeCadence < 30 || viewModel.backgroundCadence < 120 {
                    warningChip
                }
            }
        }
    }

    private var warningChip: some View {
        HStack(spacing: 10) {
            SettingsDot(tone: .warn)
            Text("Lower values use more of your GitHub API quota (5,000 / hr).")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .fill(AerieColor.warn.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .strokeBorder(AerieColor.warn.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Rate limit

    private var rateLimitCard: some View {
        card {
            if viewModel.rateLimits.isEmpty {
                Text("No rate limit data yet — polling hasn't started.")
                    .aerieFont(AerieFont.small())
                    .foregroundStyle(AerieColor.text3)
            } else {
                // Per-account columns, 30pt apart, split by 1px glass hairlines.
                HStack(alignment: .top, spacing: 30) {
                    ForEach(Array(viewModel.rateLimits.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            Rectangle()
                                .fill(AerieColor.glassLine)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                        rateLimitColumn(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rateLimitColumn(_ item: AccountRateLimitSnapshot) -> some View {
        let api = item.account.host == "github.com" ? "GITHUB API" : "GHE"
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(api) · \(item.account.login)".uppercased())
                .aerieFont(AerieFont.custom(.mono, size: 9))
                .tracking(2.3)                       // 0.26em @ 9pt
                .foregroundStyle(AerieColor.amber.opacity(0.72))
                .lineLimit(1)
            if let snap = item.snapshot {
                RateMeter(remaining: snap.remaining, limit: snap.limit, resetEpoch: snap.resetEpoch)
            } else {
                Text("not yet used")
                    .aerieFont(AerieFont.small())
                    .foregroundStyle(AerieColor.text3)
            }
        }
    }

    // MARK: - Behavior

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            behaviorRow(
                title: "Refresh on app focus",
                hint: "So you see fresh data the moment you ⌘-Tab back.",
                on: Binding(
                    get: { viewModel.refreshOnFocus },
                    set: { v in Task { await viewModel.setRefreshOnFocus(v) } }
                ),
                showDivider: true
            )
            behaviorRow(
                title: "Pause polling when app loses focus",
                hint: "Saves API quota when you're not looking.",
                on: Binding(
                    get: { viewModel.pauseOnBlur },
                    set: { v in Task { await viewModel.setPauseOnBlur(v) } }
                ),
                showDivider: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    private func behaviorRow(
        title: String,
        hint: String,
        on: Binding<Bool>,
        showDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .aerieFont(AerieFont.custom(.sans, size: 14))
                        .foregroundStyle(AerieColor.text1)
                    Text(hint)
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.text3)
                }
                Spacer(minLength: 16)
                Toggle(title, isOn: on)
                    .labelsHidden()
                    .toggleStyle(.aerie)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            if showDivider {
                Rectangle()
                    .fill(AerieColor.glassLine)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button("Reset to defaults") {
            Task { await viewModel.resetToDefaults() }
        }
        .buttonStyle(.hud(.ghost, size: .small))
    }

    // MARK: - Building blocks

    private func sectionEyebrow(_ text: String) -> some View {
        SectionEyebrow(text: text)
    }

    @ViewBuilder
    private func card<Body: View>(@ViewBuilder content: () -> Body) -> some View {
        content()
            .padding(.vertical, 22)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.card)
    }
}
