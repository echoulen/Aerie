import SwiftUI

/// Settings → Advanced main content.
///
/// Three sections plus a reset button:
///   ┌──────────────────────────────────────────────────────┐
///   │ Polling cadence                                      │
///   │   <CadenceSlider Active>                             │
///   │   <CadenceSlider Background>                         │
///   │   ⚠ warning chip (only if values are below threshold)│
///   │                                                      │
///   │ Rate limit                                           │
///   │   <login@host> + <RateMeter>  (per account)          │
///   │                                                      │
///   │ Behavior                                             │
///   │   [ ] Refresh on app focus                           │
///   │   [ ] Pause polling when app loses focus             │
///   │                                                      │
///   │                              [ Reset to defaults ]   │
///   └──────────────────────────────────────────────────────┘
///
/// Setter bindings dispatch into `Task { await viewModel.set... }` so
/// SwiftUI's synchronous binding contract is preserved while the
/// underlying persistence + cadence-apply step runs async.
struct AdvancedScreen: View {
    @Bindable var viewModel: AdvancedViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pollingSection
                rateLimitSection
                behaviorSection
                resetButton
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Polling

    private var pollingSection: some View {
        sectionCard(title: "Polling cadence") {
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
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(AerieColor.warn.opacity(0.1)))
        .overlay(Capsule().strokeBorder(AerieColor.warn.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Rate limit

    private var rateLimitSection: some View {
        sectionCard(title: "Rate limit") {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.rateLimits.isEmpty {
                    Text("No rate limit data yet — polling hasn't started.")
                        .font(AerieFont.small())
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
                                .font(AerieFont.body().weight(.medium))
                                .foregroundStyle(AerieColor.text1)
                            if let snap = item.snapshot {
                                RateMeter(remaining: snap.remaining, limit: snap.limit)
                            } else {
                                Text("not yet used")
                                    .font(AerieFont.small())
                                    .foregroundStyle(AerieColor.text3)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        sectionCard(title: "Behavior") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Refresh on app focus", isOn: Binding(
                    get: { viewModel.refreshOnFocus },
                    set: { v in Task { await viewModel.setRefreshOnFocus(v) } }
                ))
                Toggle("Pause polling when app loses focus", isOn: Binding(
                    get: { viewModel.pauseOnBlur },
                    set: { v in Task { await viewModel.setPauseOnBlur(v) } }
                ))
            }
            .toggleStyle(.switch)
            .tint(AerieColor.amber)
            .foregroundStyle(AerieColor.text1)
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        HStack {
            Spacer()
            Button("Reset to defaults") {
                Task { await viewModel.resetToDefaults() }
            }
            .buttonStyle(.plain)
            .font(AerieFont.small())
            .foregroundStyle(AerieColor.text3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AerieColor.glass1))
            .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
        }
    }

    // MARK: - Section card

    @ViewBuilder
    private func sectionCard<Body: View>(
        title: String,
        @ViewBuilder content: () -> Body
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            content()
                .padding(AerieMetric.cardPaddingV)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(.card)
        }
    }
}
