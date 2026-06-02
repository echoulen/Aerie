import SwiftUI

/// Discard-all-unstaged confirmation for a worktree. Runs `git restore .` +
/// `git clean -fd` at the worktree path. Danger tone; mirrors `DialogDiscard`
/// and `DialogDeleteWorktree`.
struct DialogWorktreeDiscard: View {
    let repo: Repository
    let worktree: WorktreeRow
    var onConfirm: () async -> String?
    var onCancel: () -> Void

    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        DialogShell(
            tone: .danger,
            title: "Discard changes in \(worktree.branchLabel)?",
            subtitle: "This runs git restore . and git clean -fd in the worktree, permanently dropping all unstaged and untracked changes. Staged changes and commits are kept.",
            primaryTitle: "Discard all unstaged",
            onPrimary: { Task { await confirm() } },
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            primaryDisabled: busy,
            loading: busy,
            loadingLabel: "Discarding…",
            progressNote: "Discarding…",
            errorMessage: errorMessage,
            icon: "arrow.counterclockwise"
        ) {
            KVList(rows: [
                KVList.Row("repository", AnyView(
                    Text("\(repo.githubOwner)/\(repo.githubRepo)")
                        .aerieFont(AerieFont.code(13))
                        .foregroundStyle(AerieColor.text1)
                )),
                KVList.Row("worktree", AnyView(
                    Text(worktree.branchLabel)
                        .aerieFont(AerieFont.code(13))
                        .foregroundStyle(AerieColor.text1)
                )),
                KVList.Row("will discard", AnyView(
                    HStack(spacing: 7) {
                        Circle()
                            .fill(AerieColor.err)
                            .frame(width: 6, height: 6)
                        Text("\(worktree.dirtyFileCount) uncommitted change\(worktree.dirtyFileCount == 1 ? "" : "s")")
                            .aerieFont(AerieFont.custom(.sans, size: 13))
                            .foregroundStyle(AerieColor.err)
                    }
                )),
            ])
        }
    }

    private func confirm() async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        errorMessage = await onConfirm()
        busy = false
    }
}
