import SwiftUI

/// Confirmation dialog for submitting an approving review on a PR. Mirrors
/// `DialogMerge`: an amber CTA tone, a compact PR preview, the account the
/// approval will be submitted as (a picker when more than one is eligible), and
/// an optional review comment.
///
/// As with the other dialogs, the view never calls `MultiAccountAPI` directly —
/// `onConfirm` is the escape hatch the integration layer wires up to call
/// `MultiAccountAPI.approvePR(...)` and then refresh.
struct DialogApprove: View {
    let context: PRReviewApproveContext
    /// Returns an error message to show in-dialog on failure, or nil on success
    /// (the caller dismisses). Mirrors `DialogMerge`'s contract.
    var onConfirm: (_ approver: GitHubAccount, _ comment: String?) async -> String?
    var onCancel: () -> Void

    @State private var selected: GitHubAccount
    @State private var comment: String = ""
    @State private var busy = false
    @State private var errorMessage: String?

    init(
        context: PRReviewApproveContext,
        onConfirm: @escaping (_ approver: GitHubAccount, _ comment: String?) async -> String?,
        onCancel: @escaping () -> Void,
        initialError: String? = nil
    ) {
        self.context = context
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selected = State(initialValue: context.resolution.defaultApprover
            ?? GitHubAccount(id: UUID(), login: "unknown", host: "github.com"))
        _errorMessage = State(initialValue: initialError)
    }

    private var pr: PullRequest { context.row.pr }
    private var repo: Repository { context.row.repo }

    var body: some View {
        DialogShell(
            tone: .warning,
            title: "Approve pull request #\(pr.number)?",
            subtitle: "Submit an approving review as \(selected.login).",
            primaryTitle: "Approve",
            onPrimary: { Task { await run() } },
            secondaryTitle: "Cancel",
            onSecondary: onCancel,
            loading: busy,
            loadingLabel: "Approving…",
            progressNote: "Submitting approval for #\(pr.number)…",
            errorMessage: errorMessage,
            icon: "checkmark.circle",
            primaryProminent: true,
            headerSpacing: 7,
            titleWeight: .regular
        ) {
            VStack(spacing: 14) {
                preview
                if context.resolution.needsPicker {
                    approverPicker
                } else {
                    KVList(rows: [
                        KVList.Row("approve as", AnyView(mono("\(selected.login) · \(selected.host)"))),
                    ])
                }
                commentField
            }
        }
    }

    // PR preview — a `repo · #N` eyebrow over the title.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(repo.githubRepo) · #\(pr.number)")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
            Text(pr.title)
                .aerieFont(AerieFont.custom(.sans, size: 14.5).weight(.light))
                .foregroundStyle(AerieColor.text1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }

    private var approverPicker: some View {
        HStack(spacing: 10) {
            Text("approve as")
                .aerieFont(AerieFont.custom(.sans, size: 12))
                .foregroundStyle(AerieColor.text3)
            Menu {
                ForEach(context.resolution.eligible) { acc in
                    Button("\(acc.login) · \(acc.host)") { selected = acc }
                }
            } label: {
                HStack(spacing: 6) {
                    mono("\(selected.login) · \(selected.host)")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AerieColor.text3)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer(minLength: 0)
        }
    }

    private var commentField: some View {
        TextField("Optional review comment", text: $comment, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(2...4)
            .aerieFont(AerieFont.custom(.sans, size: 12.5))
            .foregroundStyle(AerieColor.text1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(13))
            .foregroundStyle(AerieColor.text1)
    }

    private func run() async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = await onConfirm(selected, trimmed.isEmpty ? nil : trimmed)
        busy = false
    }
}
