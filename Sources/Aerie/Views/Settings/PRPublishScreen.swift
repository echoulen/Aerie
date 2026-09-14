import SwiftUI

/// Settings → Pull Requests: the claude-driven PR publish prompt template.
///
/// Layout follows the Advanced screen's house style: eyebrow, page title +
/// code-style subtitle, a section eyebrow, then one glass card holding the
/// monospaced template editor. Edits persist via the VM's debounced save;
/// "Reset to default" restores the built-in template.
///
/// MARK III: shared `SettingsPageHeader`, a custom/default `StatusPill`
/// (gold when customised), the editor in a recessed mono well, and the reset
/// action as a bevelled HUD key (dimmed by the style while disabled).
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
        SettingsPageHeader(
            eyebrow: "Pull Requests",
            title: "PR publish template",
            subtitle: "what claude is told when you press Create Pull Request"
        ) {
            resetButton
        }
    }

    private var templateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Variables: {{OWNER}} {{REPO}} {{DEFAULT_BRANCH}} {{CURRENT_BRANCH}} {{STATUS_SUMMARY}}")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 8)
                StatusPill(
                    text: viewModel.isCustom ? "custom" : "default",
                    tone: viewModel.isCustom ? .amber : .muted
                )
            }

            TextEditor(text: Binding(
                get: { viewModel.template },
                set: { viewModel.setTemplate($0) }
            ))
            .aerieFont(AerieFont.code(12))
            .foregroundStyle(AerieColor.text1)
            .tint(AerieColor.amber)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 360)
            .padding(10)
            .hudWell()
        }
        .padding(AerieMetric.cardPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    private var resetButton: some View {
        Button("Reset to default") {
            Task { await viewModel.resetToDefault() }
        }
        .buttonStyle(.hud(.standard, size: .small))
        .disabled(!viewModel.isCustom)
    }

    private func sectionEyebrow(_ t: String) -> some View {
        SettingsSectionLabel(text: t)
    }
}
