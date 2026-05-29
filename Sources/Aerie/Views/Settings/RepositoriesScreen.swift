import SwiftUI

/// Settings → Repositories main content.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` lines 200-310.
/// Layout:
///   ┌──────────────────────────────────────────────────────────┐
///   │ Repositories            [Refresh all] [+ Add repository] │
///   │                                                          │
///   │ ┌──────────────────────────────────────────────────────┐ │
///   │ │ RepoSettingsRow #1                                   │ │
///   │ │ ─────────────────────────────────────────────────────│ │
///   │ │ RepoSettingsRow #2                                   │ │
///   │ │ ─────────────────────────────────────────────────────│ │
///   │ │ RepoSettingsRow #3                                   │ │
///   │ └──────────────────────────────────────────────────────┘ │
///   └──────────────────────────────────────────────────────────┘
///
/// Drag-reorder via SwiftUI's `.onDrag/.onDrop` is intentionally
/// deferred — `viewModel.reorder(from:to:)` is wired and tested, but
/// the gesture plumbing is flaky enough that Phase 21's final smoke
/// pass will own it. The data path is ready when that lands.
struct RepositoriesScreen: View {
    @Bindable var viewModel: RepositoriesViewModel
    var onRefreshAll: () -> Void
    var onAddRepo: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                if !viewModel.repos.isEmpty {
                    columnLegend.padding(.top, 20)
                    listCard.padding(.top, 6)
                }
                if let error = viewModel.error {
                    Text(error)
                        .font(AerieFont.small())
                        .foregroundStyle(AerieColor.err)
                        .padding(.top, 18)
                }
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionEyebrow("REPOSITORIES")
            HStack(alignment: .firstTextBaseline) {
                Text("Tracked locally")
                    .font(AerieFont.sectionTitle())
                    .foregroundStyle(AerieColor.text1)
                Text("\(viewModel.repos.count) repositor\(viewModel.repos.count == 1 ? "y" : "ies")")
                    .font(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 16)
                Button("↻ Refresh all", action: onRefreshAll)
                    .buttonStyle(GhostButtonStyle())
                Button("+ Add repository", action: onAddRepo)
                    .buttonStyle(AmberButtonStyle())
            }
        }
    }

    // MARK: - Column legend

    // Faint guide above the list — `settings.jsx` lines 233-245. Same 5-column
    // grid as the rows, inset 20 pt to sit over the row content (the rows pad
    // 20 pt inside the card).
    private var columnLegend: some View {
        HStack(spacing: 18) {
            Color.clear.frame(width: 18, height: 1)
            legendLabel("NAME · PATH")
                .frame(maxWidth: .infinity, alignment: .leading)
            legendLabel("GITHUB · CURRENT BRANCH")
                .frame(maxWidth: .infinity, alignment: .leading)
            legendLabel("ACCOUNT")
                .frame(width: 130, alignment: .leading)
            Color.clear.frame(width: 28, height: 1)
        }
        .padding(.horizontal, 20)
    }

    private func legendLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom(AerieFont.mono, size: 9).weight(.medium))
            .tracking(1.8) // 0.20em × 9 px
            .foregroundStyle(AerieColor.text4)
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(AerieFont.eyebrow())
            .tracking(2.0)
            .foregroundStyle(AerieColor.text4)
    }

    // MARK: - List

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.repos.enumerated()), id: \.element.id) { idx, repo in
                if idx > 0 {
                    Rectangle()
                        .fill(AerieColor.glassLine)
                        .frame(height: 1)
                }
                RepoSettingsRow(
                    repo: repo,
                    accounts: viewModel.accounts,
                    onChangeAccount: { accountId in
                        Task { await viewModel.setAccount(repoId: repo.id, accountId: accountId) }
                    },
                    onRemove: {
                        Task { await viewModel.remove(id: repo.id) }
                    }
                )
            }
        }
        .glass(.card)
    }
}

// MARK: - Button styles

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AerieFont.small().weight(.medium))
            .foregroundStyle(AerieColor.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AerieColor.glass1))
            .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

private struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AerieFont.small().weight(.medium))
            .foregroundStyle(AerieColor.amber)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(AerieColor.amberSoft))
            .overlay(Capsule().strokeBorder(AerieColor.amberLine, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
