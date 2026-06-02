import SwiftUI

/// Delete-worktree confirmation. Clean → `git worktree remove`; dirty →
/// `--force` with an N-changes warning. Reuses `DialogShell` + `KVList`, danger
/// tone, matching DialogReset/DialogDiscard.
struct DialogDeleteWorktree: View {
    let repo: Repository
    let worktree: WorktreeRow
    var onConfirm: () async -> String?
    var onCancel: () -> Void

    @State private var busy = false
    @State private var errorMessage: String?

    private var dirty: Bool { worktree.isDirty && worktree.dirtyFileCount > 0 }

    var body: some View {
        DialogShell(
            tone: .danger,
            title: "Delete worktree \(worktree.branchLabel)?",
            subtitle: dirty
                ? "This worktree has \(worktree.dirtyFileCount) uncommitted change\(worktree.dirtyFileCount == 1 ? "" : "s"). Deleting runs git worktree remove --force and permanently discards them."
                : "This runs git worktree remove. Only the checkout directory is deleted — the branch and its commits stay in \(repo.name)'s shared .git/.",
            primaryTitle: dirty ? "Force-delete worktree" : "Delete worktree",
            onPrimary: { Task { await confirm() } },
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            primaryDisabled: busy,
            loading: busy,
            loadingLabel: "Removing worktree…",
            progressNote: "Removing worktree…",
            errorMessage: errorMessage,
            icon: dirty ? "exclamationmark.triangle.fill" : "trash"
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
                KVList.Row("path", AnyView(
                    Text(worktree.path.path)
                        .aerieFont(AerieFont.code(13))
                        .foregroundStyle(AerieColor.text1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                )),
                dirty
                    ? KVList.Row("will discard", AnyView(
                        HStack(spacing: 7) {
                            Circle()
                                .fill(AerieColor.err)
                                .frame(width: 6, height: 6)
                            Text("\(worktree.dirtyFileCount) uncommitted change\(worktree.dirtyFileCount == 1 ? "" : "s")")
                                .aerieFont(AerieFont.custom(.sans, size: 13))
                                .foregroundStyle(AerieColor.err)
                        }
                    ))
                    : KVList.Row("working tree", AnyView(
                        Text("clean — nothing to lose")
                            .aerieFont(AerieFont.custom(.sans, size: 13))
                            .foregroundStyle(AerieColor.ok)
                    )),
            ])

            if worktree.source == .superset {
                Text("Worktrees like this are usually created by external tools (e.g. superset). Removing it deletes the working directory, so that tool's state may no longer line up.")
                    .aerieFont(AerieFont.custom(.sans, size: 13))
                    .foregroundStyle(AerieColor.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.18)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AerieColor.glassLine, lineWidth: 1))
                    .padding(.top, 12)
            }
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
