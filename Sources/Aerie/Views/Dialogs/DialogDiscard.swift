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
    var onConfirm: () async -> String?
    var onCancel: () -> Void
    /// In-flight state for the primary button.
    @State private var busy: Bool = false
    @State private var errorMessage: String?

    init(
        repo: Repository,
        status: LocalGitStatus,
        onConfirm: @escaping () async -> String?,
        onCancel: @escaping () -> Void,
        initialError: String? = nil
    ) {
        self.repo = repo
        self.status = status
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._errorMessage = State(initialValue: initialError)
    }

    var body: some View {
        DialogShell(
            tone: .danger,
            title: "Discard all unstaged changes in \(repo.name)?",
            subtitle: "This runs git restore . + git clean -fd — every unstaged modification and untracked (new) file in the working tree is permanently dropped. Staged changes, commits, and ignored files are kept.",
            primaryTitle: "Discard changes",
            onPrimary: { Task { await runConfirm() } },
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            loading: busy,
            loadingLabel: "Discarding…",
            progressNote: "Restoring working tree to HEAD…",
            errorMessage: errorMessage,
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

    private func runConfirm() async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        // nil → success (caller dismisses); non-nil → show the error, stay open.
        errorMessage = await onConfirm()
        busy = false
    }
}
