import SwiftUI

/// Delete-worktree confirmation, presented via `.popover(isPresented:)`.
/// Clean → `git worktree remove`; dirty → `--force` with an N-changes
/// warning. Danger tone, matching `DialogWorktreeDiscard`/`DialogDiscard`.
struct DialogDeleteWorktree: View {
    let repo: Repository
    let worktree: WorktreeRow
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var dirty: Bool { worktree.isDirty && worktree.dirtyFileCount > 0 }

    var body: some View {
        ActionPopoverShell(
            tone: .danger,
            title: "Delete worktree \(worktree.branchLabel)?",
            subtitle: dirty
                ? "This worktree has \(worktree.dirtyFileCount) uncommitted change\(worktree.dirtyFileCount == 1 ? "" : "s"). Deleting runs git worktree remove --force and permanently discards them."
                : "This runs git worktree remove. Only the checkout directory is deleted — the branch and its commits stay in \(repo.name)'s shared .git/.",
            primaryTitle: dirty ? "Force-delete worktree" : "Delete worktree",
            onPrimary: onConfirm,
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
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
}
