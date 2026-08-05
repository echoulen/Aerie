import SwiftUI

/// Confirmation content for hard-resetting a repo to its origin default
/// branch, presented via `.popover(isPresented:)` anchored to the repo card's
/// Reset button. Danger tone + a KV summary of the repo's current local
/// state. Carries no busy/error state of its own — see `DialogMerge`'s doc
/// comment for why.
struct DialogReset: View {
    let repo: Repository
    let status: LocalGitStatus
    var onConfirm: () -> Void
    var onCancel: () -> Void
    /// When non-nil, the confirm flow also force-deletes this merged branch, and
    /// the dialog says so. Callers must only set this when
    /// `mergedBranch.branch == status.currentBranch` — `MergedBranchSync`
    /// guarantees that.
    var mergedBranch: MergedBranchInfo? = nil

    var body: some View {
        ActionPopoverShell(
            tone: .danger,
            title: mergedBranch == nil
                ? "Hard reset \(repo.name) to origin/\(repo.defaultBranch)?"
                : "Reset \(repo.name) & delete merged branch?",
            subtitle: "This will run git reset --hard. Local commits and uncommitted changes on the current branch will be discarded.",
            primaryTitle: mergedBranch == nil
                ? "Reset to origin/\(repo.defaultBranch)"
                : "Reset & delete branch",
            onPrimary: onConfirm,
            secondaryTitle: "Cancel",
            onSecondary: onCancel
        ) {
            KVList(rows: kvRows)
        }
    }

    // MARK: - KV rows

    private var kvRows: [KVList.Row] {
        var rows: [KVList.Row] = [
            KVList.Row("repository", AnyView(mono("\(repo.githubOwner)/\(repo.githubRepo)"))),
            KVList.Row("current branch", AnyView(mono(status.currentBranch))),
            KVList.Row("working tree", AnyView(workingTreeValue)),
            KVList.Row("unpushed", AnyView(unpushedValue)),
            KVList.Row("target", AnyView(mono("origin/\(repo.defaultBranch) @ \(shortSha)"))),
        ]
        if let note = Self.deleteBranchNote(mergedBranch) {
            rows.append(KVList.Row("delete branch", AnyView(mono(note))))
        }
        return rows
    }

    // MARK: - Styled row values (mirrors the design's coloured KVList values)

    private var shortSha: String { String(status.originDefaultSha.prefix(7)) }

    private func mono(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(13))
            .foregroundStyle(AerieColor.text1)
    }

    @ViewBuilder
    private var workingTreeValue: some View {
        if status.isDirty {
            HStack(spacing: 7) {
                Circle().fill(AerieColor.err).frame(width: 6, height: 6)
                Text("dirty · \(status.dirtyFileCount) \(status.dirtyFileCount == 1 ? "file" : "files") changed")
                    .aerieFont(AerieFont.custom(.sans, size: 13))
                    .foregroundStyle(AerieColor.err)
            }
        } else {
            Text("clean")
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.text3)
        }
    }

    @ViewBuilder
    private var unpushedValue: some View {
        if status.unpushedCommits > 0 {
            Text("\(status.unpushedCommits) \(status.unpushedCommits == 1 ? "commit" : "commits") on this branch")
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.amber)
        } else {
            Text("none")
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.text3)
        }
    }

    /// The "delete branch" KV value, or nil when there's no merged branch to
    /// clean up. Static + internal so it's unit-testable without rendering.
    static func deleteBranchNote(_ mergedBranch: MergedBranchInfo?) -> String? {
        guard let m = mergedBranch else { return nil }
        return "\(m.branch) (merged in #\(m.prNumber))"
    }
}
