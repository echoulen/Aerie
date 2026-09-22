import SwiftUI

/// Settings → AI Review: the editable guidance inside the review prompt.
///
/// Visual contract: `src/v2/publish.jsx` `AIReviewGuidanceScreen` — page
/// header with a FIRST PASS / FOLLOW-UP segmented switch, an explainer card
/// (gold ◈, approximate prompt size), then three stacked blocks: a locked
/// context header (dashed glass hairline, mono 11 text-4), the editable
/// guidance (black/0.44 well, gold rim and glow, mono 12, "custom"/"default"
/// pill + Reset), and the locked diff + JSON contract.
struct AIReviewScreen: View {
    @Bindable var viewModel: AIReviewGuidanceViewModel
    @Environment(\.interfaceFontScale) private var fontScale

    var body: some View {
        let tab = viewModel.tab
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsPageHeader(
                    eyebrow: "AI Review",
                    title: "Review guidance",
                    subtitle: "what claude is told to look for",
                    subtitleSize: 12.5
                ) {
                    tabSwitch
                }
                explainer.padding(.top, 20)
                VStack(alignment: .leading, spacing: 14) {
                    lockedBlock(label: "1 · context header · generated", body: viewModel.lockedHead(tab))
                    editableBlock(tab)
                    lockedBlock(
                        label: tab == .firstPass ? "3 · diff + json contract · generated" : "3 · reply guard + json contract · generated",
                        body: viewModel.lockedTail(tab))
                }
                .padding(.top, 18)
            }
            .settingsPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { Task { await viewModel.flush() } }
    }

    // MARK: Header

    private var tabSwitch: some View {
        HStack(spacing: 2) {
            ForEach(AIReviewGuidanceViewModel.Tab.allCases) { tab in
                let isSelected = viewModel.tab == tab
                Button { viewModel.tab = tab } label: {
                    Text(tab.title.uppercased())
                        .aerieFont(AerieFont.small().weight(.semibold))
                        .tracking(0.96)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? AerieColor.amber : AerieColor.text3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AerieMetric.radiusPill)
                                .fill(isSelected ? AerieColor.glass3 : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AerieMetric.radiusPill)
                                .strokeBorder(isSelected ? AerieColor.amberLine : Color.clear, lineWidth: 1)
                        )
                        .shadow(color: isSelected ? AerieColor.amberGlow.opacity(0.35) : .clear, radius: 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.40))
        .clipShape(RoundedRectangle(cornerRadius: AerieMetric.radiusPill))
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }

    private var explainer: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("◈")
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.amber)
            Text("The prompt is assembled from three parts. The context header and the JSON verdict contract are fixed — Aerie parses the reply and editing them would break the verdict. The middle section is yours.")
                .aerieFont(AerieFont.custom(.sans, size: 12.5))
                .foregroundStyle(AerieColor.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("≈ \(Self.tokenLabel(viewModel.approxTokens(viewModel.tab))) tokens + diff")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    static func tokenLabel(_ n: Int) -> String {
        n < 1000 ? "\(n)" : String(format: "%.1fk", Double(n) / 1000)
    }

    // MARK: Blocks

    private func lockedBlock(label: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HudNote(text: label)
                Spacer(minLength: 0)
                StatusPill(text: "⊟ locked", tone: .muted)
            }
            Text(body)
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
                .lineSpacing(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 13)
                .background(Rectangle().fill(Color.black.opacity(0.30)))
                .overlay(
                    Rectangle().strokeBorder(AerieColor.glassLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
    }

    private func editableBlock(_ tab: AIReviewGuidanceViewModel.Tab) -> some View {
        let custom = viewModel.isCustom(tab)
        let text = Binding(
            get: { viewModel.text(tab) },
            set: { viewModel.setText($0, for: tab) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HudNote(
                    text: tab == .firstPass ? "2 · your review guidance · editable" : "2 · follow-up guidance · editable",
                    color: AerieColor.amber)
                Spacer(minLength: 0)
                StatusPill(text: custom ? "custom" : "default", tone: custom ? .amber : .neutral)
                Button("Reset") { Task { await viewModel.reset(tab) } }
                    .buttonStyle(.hud(.ghost, size: .small))
                    .disabled(!custom)
            }
            TextEditor(text: text)
                .font(AerieFont.code(12).resolve(scale: fontScale))
                .foregroundStyle(AerieColor.text2)
                .lineSpacing(8)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .frame(height: 360)
                .background(Rectangle().fill(Color.black.opacity(0.44)))
                .overlay(Rectangle().strokeBorder(AerieColor.amberLine, lineWidth: 1))
                .shadow(color: AerieColor.amberGlow.opacity(0.35), radius: 15)
                .accessibilityLabel(tab == .firstPass ? "Review guidance" : "Follow-up guidance")
            // Truncates rather than widening the page past the window.
            HudNote(text: tab == .firstPass
                ? "saves as you type · applies to the next review · blank uses the default"
                : "re-reviews only · previous review + replies are appended automatically",
                truncates: true)
        }
    }
}
