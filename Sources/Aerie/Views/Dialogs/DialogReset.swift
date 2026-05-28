import SwiftUI

/// Confirmation dialog for hard-resetting a repo to its origin default branch.
/// Danger tone (red ring) + a KV summary of the repo's current local state.
/// The view never calls `GitService` directly — `onConfirm` is the escape
/// hatch the integration layer wires up to call `GitService.hardResetToOrigin`
/// and then trigger a repo refresh (Phase-21 concern).
struct DialogReset: View {
    let repo: Repository
    let status: LocalGitStatus
    /// Closure invoked when the user confirms; the caller decides the actual
    /// reset target (default branch is read from `repo.defaultBranch`).
    var onConfirm: () async -> Void
    var onCancel: () -> Void
    /// In-flight state for the primary button.
    @State private var busy: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        DialogShell(
            tone: .danger,
            title: "Hard reset \(repo.name) to origin/\(repo.defaultBranch)?",
            subtitle: "This is destructive and cannot be undone.",
            primaryTitle: "Reset to origin/\(repo.defaultBranch)",
            onPrimary: { Task { await runConfirm() } },
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            primaryDisabled: busy,
            errorMessage: errorMessage
        ) {
            KVList(pairs: [
                ("Repository", "\(repo.githubOwner)/\(repo.githubRepo)"),
                ("Current branch", status.currentBranch),
                ("Working tree", status.isDirty ? "\(status.dirtyFileCount) modified" : "clean"),
                ("Ahead of origin", "\(status.aheadOfDefault)"),
                ("Behind origin", "\(status.behindOfDefault)"),
                ("Unpushed commits", "\(status.unpushedCommits)"),
            ])
        }
    }

    private func runConfirm() async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        await onConfirm()
        busy = false
    }
}
