import SwiftUI

/// Confirmation dialog for discarding all UNSTAGED changes in a repo's working
/// tree (`git restore .`). Danger tone (red ring) + a KV summary scoping exactly
/// what is dropped vs kept.
///
/// Mirrors `DialogReset`'s contract: the view never calls `GitService` directly
/// — `onConfirm` is the escape hatch the integration layer wires up to call
/// `GitService.discardUnstaged` and then trigger a repo refresh. It returns an
/// error message to display in-dialog on failure, or `nil` on success (the
/// caller dismisses).
///
/// Visual contract: `docs/superpowers/design/v2/dialogs.jsx` `DialogDiscard`.
struct DialogDiscard: View {
    let repo: Repository
    let status: LocalGitStatus
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ActionPopoverShell(
            tone: .danger,
            title: "Discard all unstaged changes in \(repo.name)?",
            subtitle: "This runs git restore . + git clean -fd — every unstaged modification and untracked (new) file in the working tree is permanently dropped. Staged changes, commits, and ignored files are kept.",
            primaryTitle: "Discard changes",
            onPrimary: onConfirm,
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            icon: "arrow.counterclockwise"
        ) {
            KVList(rows: [
                KVList.Row("repository", AnyView(mono("\(repo.githubOwner)/\(repo.githubRepo)"))),
                KVList.Row("current branch", AnyView(mono(status.currentBranch))),
                KVList.Row("will discard", AnyView(willDiscardValue)),
                KVList.Row("kept", AnyView(keptValue)),
            ])
        }
    }

    // MARK: - Styled row values (mirror the design's coloured KVList values)

    private func mono(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(13))
            .foregroundStyle(AerieColor.text1)
    }

    /// What `git restore .` drops — the unstaged tracked-file edits. Our
    /// `LocalGitStatus` tracks a single dirty count (not a modified/untracked
    /// split), so we surface that, in danger red.
    private var willDiscardValue: some View {
        let n = status.dirtyFileCount
        return Text("\(n) \(n == 1 ? "file" : "files") changed")
            .aerieFont(AerieFont.custom(.sans, size: 13))
            .foregroundStyle(AerieColor.err)
    }

    /// Reassures the user the op is scoped — staged work and commits survive.
    private var keptValue: some View {
        Text("staged changes · local commits")
            .aerieFont(AerieFont.custom(.sans, size: 13))
            .foregroundStyle(AerieColor.ok)
    }
}
