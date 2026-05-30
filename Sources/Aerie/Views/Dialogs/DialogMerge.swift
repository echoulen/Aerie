import SwiftUI

/// Confirmation dialog for squash-merging a pull request. Warning tone
/// (amber ring) + a compact PR preview (title, owner/repo, number, author,
/// CI + review chips) above a KV summary (method, commit subject, source
/// branch, account).
///
/// As with `DialogReset`, the view never calls `MultiAccountAPI` directly —
/// `onConfirm` is the escape hatch the integration layer wires up to call
/// `MultiAccountAPI.mergePR(owner:repo:number:method:)` and then refresh.
struct DialogMerge: View {
    let pr: PullRequest
    let repo: Repository
    let account: GitHubAccount
    /// Closure invoked when the user confirms. Returns an error message to
    /// display in-dialog on failure, or `nil` on success — in which case the
    /// caller dismisses the dialog. Mirrors `DialogReset`'s contract so the
    /// integration layer can flow a merge failure back into the open dialog.
    var onConfirm: () async -> String?
    var onCancel: () -> Void
    @State private var busy: Bool = false
    @State private var errorMessage: String?

    init(
        pr: PullRequest,
        repo: Repository,
        account: GitHubAccount,
        onConfirm: @escaping () async -> String?,
        onCancel: @escaping () -> Void,
        initialError: String? = nil
    ) {
        self.pr = pr
        self.repo = repo
        self.account = account
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._errorMessage = State(initialValue: initialError)
    }

    var body: some View {
        DialogShell(
            tone: .warning,
            title: "Merge PR #\(pr.number)?",
            subtitle: pr.title,
            primaryTitle: "Squash and merge",
            onPrimary: { Task { await runConfirm() } },
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            primaryDisabled: busy,
            errorMessage: errorMessage
        ) {
            VStack(spacing: 12) {
                preview
                KVList(pairs: [
                    ("Method", "squash"),
                    ("Commit subject", "\(pr.title) (#\(pr.number))"),
                    ("Source branch", pr.sourceBranch),
                    ("Account", "\(account.login) · \(account.host)"),
                ])
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(repo.githubOwner)/\(repo.githubRepo)")
                    .aerieFont(AerieFont.small())
                    .foregroundStyle(AerieColor.text2)
                Text("#\(pr.number)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text3)
                Spacer()
                Text("by \(pr.authorLogin)")
                    .aerieFont(AerieFont.small())
                    .foregroundStyle(AerieColor.text3)
            }
            Text(pr.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AerieColor.text1)
            HStack(spacing: 8) {
                CIChip(state: pr.ciState)
                ReviewChip(state: pr.reviewState)
            }
        }
        .padding(14)
        .background(AerieColor.glass1)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
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
