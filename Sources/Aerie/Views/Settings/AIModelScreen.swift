import SwiftUI

/// Settings → AI Model: the Claude model used by both AI Review and Create
/// Pull Request.
///
/// Visual contract: `src/v2/publish.jsx` `SettingsAIModel` — page header, a
/// MODEL eyebrow, and one `.hud-corners` card: a mono explainer ("claude" and
/// "--model" in gold) above a stack of radio rows, one per `ClaudeModel`. The
/// selected row is a gold wash with a gold rim and glow, a gold radio core,
/// a semibold name and a gold `--model` flag; the rest sit in black/0.26
/// wells. Choosing a row persists via `AIModelViewModel.setModel`.
struct AIModelScreen: View {
    @Bindable var viewModel: AIModelViewModel
    // Read for the concatenated-Text explainer, which can't use `.aerieFont`.
    @Environment(\.interfaceFontScale) private var fontScale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                SectionEyebrow(text: "Model").padding(.top, 28)
                modelCard.padding(.top, 10)
            }
            .settingsPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pageHeader: some View {
        SettingsPageHeader(
            eyebrow: "AI Model",
            title: "Model",
            subtitle: "used by AI Review",
            subtitleSize: 12.5
        )
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("AI Review runs the ")
                + Text("claude").foregroundStyle(AerieColor.amber)
                + Text(" CLI with ")
                + Text("--model").foregroundStyle(AerieColor.amber)
                + Text(" set to this value."))
                .font(AerieFont.code(11).resolve(scale: fontScale))
                .foregroundStyle(AerieColor.text3)

            VStack(spacing: 8) {
                ForEach(ClaudeModel.allCases) { model in
                    optionRow(model)
                }
            }
            .padding(.top, 14)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
        .overlay(HudCorners())
    }

    private func optionRow(_ model: ClaudeModel) -> some View {
        let selected = viewModel.selected == model
        let shape = RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
        return Button {
            Task { await viewModel.setModel(model) }
        } label: {
            HStack(spacing: 14) {
                radio(selected: selected)
                Text(model.displayName)
                    .aerieFont(AerieFont.custom(.sans, size: 14).weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AerieColor.text1 : AerieColor.text2)
                Text("--model \(model.rawValue)")
                    .aerieFont(AerieFont.code(11.5))
                    .foregroundStyle(selected ? AerieColor.amber : AerieColor.text4)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(shape.fill(selected ? AerieColor.amberSoft : Color.black.opacity(0.26)))
            .overlay(shape.strokeBorder(selected ? AerieColor.amberLine : AerieColor.glassLine, lineWidth: 1))
            .shadow(color: selected ? AerieColor.amberGlow.opacity(0.5) : .clear, radius: selected ? 14 : 0)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.18), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func radio(selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? AerieColor.amber : AerieColor.glassLine2, lineWidth: 1)
            if selected {
                Circle()
                    .fill(AerieColor.amber)
                    .frame(width: 6, height: 6)          // ~38% of the 14pt radio
                    .shadow(color: AerieColor.amberGlow, radius: 6)
            }
        }
        .frame(width: 14, height: 14)
    }
}
