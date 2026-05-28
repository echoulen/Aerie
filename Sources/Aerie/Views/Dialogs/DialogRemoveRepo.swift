import SwiftUI

/// Confirmation dialog for removing a repo from Aerie's tracked list.
/// Neutral tone — this is not a destructive on-disk operation; the explicit
/// "Will delete: nothing on disk" KV row exists so the user is unambiguous
/// about that before clicking through.
struct DialogRemoveRepo: View {
    let repo: Repository
    var onConfirm: () async -> Void
    var onCancel: () -> Void
    @State private var busy: Bool = false

    var body: some View {
        DialogShell(
            tone: .neutral,
            title: "Remove \(repo.name) from Aerie?",
            subtitle: "This only removes it from the tracked list. Nothing on disk will change.",
            primaryTitle: "Remove",
            onPrimary: { Task { await runConfirm() } },
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            primaryDisabled: busy
        ) {
            KVList(pairs: [
                ("Local path", repo.localPath.path),
                ("GitHub", "\(repo.githubOwner)/\(repo.githubRepo)"),
                ("Will delete", "nothing on disk"),
            ])
        }
    }

    private func runConfirm() async {
        guard !busy else { return }
        busy = true
        await onConfirm()
        busy = false
    }
}
