import SwiftUI

/// Settings → Pull Requests: the claude-driven PR publish prompt template.
///
/// Visual contract: `src/v2/publish.jsx` `SettingsPRTemplate` — page header
/// with a `.btn ghost sm` "Reset to default" (dimmed to 0.45 while the
/// template is already the default), a PROMPT TEMPLATE eyebrow, and one
/// `.hud-corners` card: the variables line (names in gold) with a
/// custom/default pill, the mono editor in a black/0.42 well, and a
/// `.hud-note` save footer with size/line counts. Edits persist via the VM's
/// debounced save; "Reset to default" restores the built-in template.
struct PRPublishScreen: View {
    @Bindable var viewModel: PRPublishViewModel
    // Read for the concatenated-Text variables line, which can't use `.aerieFont`.
    @Environment(\.interfaceFontScale) private var fontScale

    private static let variables = "{{OWNER}} {{REPO}} {{DEFAULT_BRANCH}} {{CURRENT_BRANCH}} {{STATUS_SUMMARY}}"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                SectionEyebrow(text: "Prompt template").padding(.top, 28)
                templateCard.padding(.top, 10)
            }
            .settingsPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pageHeader: some View {
        SettingsPageHeader(
            eyebrow: "Pull Requests",
            title: "PR publish template",
            subtitle: "what claude is told when you press Create Pull Request",
            subtitleSize: 12.5
        ) {
            resetButton
        }
    }

    private var templateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                (Text("Variables: ").foregroundStyle(AerieColor.text3)
                    + Text(Self.variables).foregroundStyle(AerieColor.amber))
                    .font(AerieFont.code(11).resolve(scale: fontScale))
                    .lineLimit(2)
                Spacer(minLength: 8)
                StatusPill(
                    text: viewModel.isCustom ? "custom" : "default",
                    tone: viewModel.isCustom ? .amber : .neutral
                )
            }

            TextEditor(text: Binding(
                get: { viewModel.template },
                set: { viewModel.setTemplate($0) }
            ))
            .aerieFont(AerieFont.code(12))
            .lineSpacing(9)                              // line-height 1.75 @ 12pt
            .foregroundStyle(AerieColor.text2)
            .tint(AerieColor.amber)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 360)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .hudWell(fill: 0.42)
            .padding(.top, 12)

            HStack {
                HudNote(text: "saved · debounced 500ms")
                Spacer()
                Text("\(viewModel.template.count) chars · \(lineCount) lines")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
        .overlay(HudCorners())
    }

    private var lineCount: Int {
        viewModel.template.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    private var resetButton: some View {
        Button("Reset to default") {
            Task { await viewModel.resetToDefault() }
        }
        .buttonStyle(.hud(.ghost, size: .small))
        .disabled(!viewModel.isCustom)
    }
}
