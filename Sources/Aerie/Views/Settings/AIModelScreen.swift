import SwiftUI

/// Settings → AI Model: the Claude model used by both AI Review and Create
/// Pull Request. Layout follows the Pull Requests screen's house style:
/// eyebrow, page title + code-style subtitle, a section eyebrow, then one
/// glass card holding the model picker. MARK III: shared `SettingsPageHeader`
/// and mono section label; the native menu picker sits in a recessed well.
struct AIModelScreen: View {
    @Bindable var viewModel: AIModelViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                sectionEyebrow("MODEL").padding(.top, 28)
                modelCard.padding(.top, 10)
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pageHeader: some View {
        SettingsPageHeader(
            eyebrow: "AI Model",
            title: "Model",
            subtitle: "used by AI Review and Create Pull Request"
        )
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Both features run the claude CLI with --model set to this value.")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text3)

            Picker("Model", selection: Binding(
                get: { viewModel.selected },
                set: { newValue in Task { await viewModel.setModel(newValue) } }
            )) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(AerieColor.amber)
            .frame(maxWidth: 320, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .hudWell()
        }
        .padding(AerieMetric.cardPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    private func sectionEyebrow(_ t: String) -> some View {
        SettingsSectionLabel(text: t)
    }
}
