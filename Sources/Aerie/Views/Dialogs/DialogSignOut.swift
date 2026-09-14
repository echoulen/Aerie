import SwiftUI

/// Confirmation dialog for signing a GitHub account out of Aerie. Danger tone
/// with a `.btn.danger` primary; the KV body lists the account, the repos that
/// currently use it as their primary (they'll lose API access until they
/// assign a different account), and a note on what sign-out does.
///
/// Visual contract: `v2/dialogs.jsx` `DialogSignOut`.
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
            primaryDisabled: busy,
            icon: "key"
        ) {
            KVList(rows: [
                KVList.Row("account", AnyView(
                    Text("\(account.login) @ \(account.host)")
                        .aerieFont(AerieFont.code(13))
                        .foregroundStyle(AerieColor.text1)
                )),
                KVList.Row("affected", AnyView(affectedValue)),
                KVList.Row("note", AnyView(
                    Text("Aerie will run gh auth logout for this account, removing its token from the gh keyring. Sign back in any time with gh auth login.")
                        .aerieFont(AerieFont.custom(.sans, size: 13))
                        .foregroundStyle(AerieColor.text3)
                        .fixedSize(horizontal: false, vertical: true)
                )),
            ])
        }
    }

    /// "N repositories: a, b" with the repo names in mono text-2, or "none".
    @ViewBuilder
    private var affectedValue: some View {
        if affectedRepos.isEmpty {
            Text("none")
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.text3)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(affectedRepos.count) \(affectedRepos.count == 1 ? "repository" : "repositories"):")
                    .aerieFont(AerieFont.custom(.sans, size: 13))
                    .foregroundStyle(AerieColor.text1)
                ForEach(affectedRepos) { repo in
                    Text("\(repo.githubOwner)/\(repo.githubRepo)")
                        .aerieFont(AerieFont.code(13))
                        .foregroundStyle(AerieColor.text2)
                }
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
