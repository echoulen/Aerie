import SwiftUI

/// A single repository row inside the Settings → Repositories list.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` lines 255-303.
/// Layout:
///   ┌────────────────────────────────────────────────────────────┐
///   │ ☰  <name>          <owner/repo>          [Account ▼]   ×   │
///   │    ~/path           branch: main                           │
///   └────────────────────────────────────────────────────────────┘
///
/// The drag-grip glyph (`line.3.horizontal`) is rendered here but the
/// actual `.onDrag/.onDrop` wiring lives at the list level
/// (`RepositoriesScreen`), since SwiftUI's drag API works on whole
/// rows, not on individual sub-views. For Phase 13.2 we just paint the
/// affordance — drag-reorder is deferred (see `RepositoriesScreen`).
struct RepoSettingsRow: View {
    let repo: Repository
    let accounts: [GitHubAccount]
    var onChangeAccount: (UUID) -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            grip
            nameAndPath
            githubAndBranch
            Spacer()
            accountDropdown
            removeButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Pieces

    private var grip: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AerieColor.text3)
            .frame(width: 18)
    }

    private var nameAndPath: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(repo.name)
                .font(AerieFont.body().weight(.medium))
                .foregroundStyle(AerieColor.text1)
            Text(collapsedPath(repo.localPath.path))
                .font(AerieFont.code(11))
                .foregroundStyle(AerieColor.text3)
        }
        .frame(width: 220, alignment: .leading)
    }

    private var githubAndBranch: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(repo.githubOwner)/\(repo.githubRepo)")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
            Text("branch: \(repo.defaultBranch)")
                .font(AerieFont.code(11))
                .foregroundStyle(AerieColor.text3)
        }
        .frame(width: 200, alignment: .leading)
    }

    private var accountDropdown: some View {
        Menu {
            ForEach(accounts) { account in
                Button("\(account.login) @ \(account.host)") {
                    onChangeAccount(account.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentAccountLabel)
                    .font(AerieFont.small())
                    .foregroundStyle(AerieColor.text2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(AerieColor.text3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(AerieColor.glass1))
            .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var currentAccountLabel: String {
        guard let acc = accounts.first(where: { $0.id == repo.primaryAccountId }) else {
            return "(no account)"
        }
        return acc.login
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AerieColor.text3)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AerieColor.glass1))
                .overlay(Circle().strokeBorder(AerieColor.glassLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Collapses a local path starting with the user's home directory
    /// to a `~/...` form, otherwise returns the path as-is.
    private func collapsedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + String(path.dropFirst(home.count))
    }
}
