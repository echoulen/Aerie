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
            VStack(alignment: .leading, spacing: 20) {
                header
                listCard
                if let error = viewModel.error {
                    Text(error)
                        .font(AerieFont.small())
                        .foregroundStyle(AerieColor.err)
                }
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("Repositories")
                .font(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            Spacer()
            Button("Refresh all", action: onRefreshAll)
                .buttonStyle(GhostButtonStyle())
            Button("+ Add repository", action: onAddRepo)
                .buttonStyle(AmberButtonStyle())
        }
    }

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
    }
}
