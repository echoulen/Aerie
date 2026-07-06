import SwiftUI

/// Settings → Pull Requests: the claude-driven PR publish prompt template.
///
/// Layout follows the Advanced screen's house style: eyebrow, page title +
/// code-style subtitle, a section eyebrow, then one glass card holding the
/// monospaced template editor. Edits persist via the VM's debounced save;
/// "Reset to default" restores the built-in template.
struct PRPublishScreen: View {
    @Bindable var viewModel: PRPublishViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                sectionEyebrow("PROMPT TEMPLATE").padding(.top, 28)
                templateCard.padding(.top, 10)
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionEyebrow("PULL REQUESTS")
            HStack(alignment: .firstTextBaseline) {
                Text("PR publish template")
                    .aerieFont(AerieFont.sectionTitle())
                    .foregroundStyle(AerieColor.text1)
                Text("what claude is told when you press Create Pull Request")
                    .aerieFont(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 16)
                resetButton
            }
        }
    }

    private var templateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Variables: {{OWNER}} {{REPO}} {{DEFAULT_BRANCH}} {{CURRENT_BRANCH}} {{STATUS_SUMMARY}}")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 8)
                Text(viewModel.isCustom ? "custom" : "default")
                    .aerieFont(AerieFont.custom(.sans, size: 10))
                    .foregroundStyle(viewModel.isCustom ? AerieColor.amber : AerieColor.text4)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule(style: .continuous)
                        .fill(viewModel.isCustom ? AerieColor.amberSoft : AerieColor.glass2))
                    .overlay(Capsule(style: .continuous)
                        .strokeBorder(viewModel.isCustom ? AerieColor.amberLine : AerieColor.glassLine, lineWidth: 1))
            }

            TextEditor(text: Binding(
                get: { viewModel.template },
                set: { viewModel.setTemplate($0) }
            ))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(AerieColor.text1)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 360)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AerieColor.glass2))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
        }
        .padding(AerieMetric.cardPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    private var resetButton: some View {
        Button {
            Task { await viewModel.resetToDefault() }
        } label: {
            Text("Reset to default")
                .aerieFont(AerieFont.custom(.sans, size: 12).weight(.medium))
                .foregroundStyle(AerieColor.text2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AerieColor.glass2))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isCustom)
        .opacity(viewModel.isCustom ? 1 : 0.5)
    }

    private func sectionEyebrow(_ t: String) -> some View {
        Text(t)
            .aerieFont(AerieFont.eyebrow())
            .tracking(2.0)
            .foregroundStyle(AerieColor.text4)
    }
}
