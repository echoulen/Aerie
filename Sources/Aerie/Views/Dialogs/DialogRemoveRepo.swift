import SwiftUI

/// Confirmation dialog for removing a repo from Aerie's tracked list.
/// Neutral tone — this is not a destructive on-disk operation — but, per the
/// design, a `.btn.danger` primary. The explicit "will delete: nothing" KV row
/// exists so the user is unambiguous about that before clicking through.
///
/// Visual contract: `v2/dialogs.jsx` `DialogRemoveRepo`.
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
            primaryDisabled: busy,
            primaryVariant: .danger,
            icon: "trash"
        ) {
            KVList(rows: [
                KVList.Row("display name", AnyView(
                    Text(repo.name)
                        .aerieFont(AerieFont.custom(.sans, size: 13))
                        .foregroundStyle(AerieColor.text1)
                )),
                KVList.Row("path", AnyView(mono(repo.localPath.path))),
                KVList.Row("github", AnyView(mono("\(repo.githubOwner)/\(repo.githubRepo)"))),
                KVList.Row("will delete", AnyView(
                    Text("nothing — files are untouched")
                        .aerieFont(AerieFont.custom(.sans, size: 13))
                        .foregroundStyle(AerieColor.ok)
                )),
            ])
        }
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(13))
            .foregroundStyle(AerieColor.text1)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func runConfirm() async {
        guard !busy else { return }
        busy = true
        await onConfirm()
        busy = false
    }
}
