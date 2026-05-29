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
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionEyebrow("ADVANCED")
            HStack(alignment: .firstTextBaseline) {
                Text("Polling & rate limits")
                    .aerieFont(AerieFont.sectionTitle())
                    .foregroundStyle(AerieColor.text1)
                Text("how often Aerie refreshes")
                    .aerieFont(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 16)
                resetButton
            }
        }
    }

    // MARK: - Polling

    private var pollingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
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
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AerieColor.warn)
            Text("Lower cadences may hit GitHub's rate limits faster.")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(AerieColor.warn.opacity(0.1)))
        .overlay(Capsule().strokeBorder(AerieColor.warn.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Rate limit

    private var rateLimitCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.rateLimits.isEmpty {
                    Text("No rate limit data yet — polling hasn't started.")
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.text3)
                } else {
                    ForEach(Array(viewModel.rateLimits.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            Rectangle()
                                .fill(AerieColor.glassLine)
                                .frame(height: 1)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(item.account.login) @ \(item.account.host)")
                                .aerieFont(AerieFont.body().weight(.medium))
                                .foregroundStyle(AerieColor.text1)
                            if let snap = item.snapshot {
                                RateMeter(remaining: snap.remaining, limit: snap.limit)
                            } else {
                                Text("not yet used")
                                    .aerieFont(AerieFont.small())
                                    .foregroundStyle(AerieColor.text3)
                            }
                        }
                    }
                }
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
                        .aerieFont(AerieFont.body())
                        .foregroundStyle(AerieColor.text1)
                    Text(hint)
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.text3)
                }
                Spacer(minLength: 16)
                Toggle("", isOn: on)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AerieColor.amber)
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
        .buttonStyle(.plain)
        .aerieFont(AerieFont.small())
        .foregroundStyle(AerieColor.text3)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(AerieColor.glass1))
        .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }

    // MARK: - Building blocks

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.eyebrow())
            .tracking(2.0)
            .foregroundStyle(AerieColor.text4)
    }

    @ViewBuilder
    private func card<Body: View>(@ViewBuilder content: () -> Body) -> some View {
        content()
            .padding(AerieMetric.cardPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.card)
    }
}
