import SwiftUI

/// Confirmation dialog for signing a GitHub account out of Aerie. Danger
/// tone (red ring); the body lists repos that currently use this account as
/// their primary so the user understands the blast radius — they'll lose
/// API access on those repos until they assign a different account.
struct DialogSignOut: View {
    let account: GitHubAccount
    /// Repositories whose primary account is `account`. They lose API access.
    let affectedRepos: [Repository]
    var onConfirm: () async -> Void
    var onCancel: () -> Void
    @State private var busy: Bool = false

    var body: some View {
        DialogShell(
            tone: .danger,
            title: "Sign out \(account.login) @ \(account.host)?",
            subtitle: affectedRepos.isEmpty
                ? "No repos use this account as primary."
                : "\(affectedRepos.count) repos use this account as primary and will lose API access until you assign a different account.",
            primaryTitle: "Sign out",
            onPrimary: { Task { await runConfirm() } },
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            primaryDisabled: busy
        ) {
            if affectedRepos.isEmpty {
                Text("Aerie will run gh auth logout for this account, removing its token from the gh keyring. Sign back in any time with gh auth login.")
                    .font(AerieFont.small())
                    .foregroundStyle(AerieColor.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Affected repos")
                        .font(AerieFont.eyebrow())
                        .foregroundStyle(AerieColor.text3)
                    ForEach(affectedRepos) { repo in
                        Text("\(repo.githubOwner)/\(repo.githubRepo)")
                            .font(AerieFont.code(11))
                            .foregroundStyle(AerieColor.text2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AerieColor.glass1)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                )
            }
        }
    }

    private func runConfirm() async {
        guard !busy else { return }
        busy = true
        await onConfirm()
        busy = false
    }
}
