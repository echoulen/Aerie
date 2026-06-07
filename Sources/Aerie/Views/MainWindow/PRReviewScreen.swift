import SwiftUI

/// What the Approve dialog needs: the PR being reviewed plus the resolved set of
/// accounts that may approve it (the author can't approve their own PR).
struct PRReviewApproveContext: Identifiable, Equatable {
    let row: PRRow
    let resolution: ApproverResolution
    var id: UUID { row.id }
}

/// The code review screen: a drill-in detail page (replacing the PR list) that
/// shows a PR's unified diff in-app, with an Approve action. Reachable from a
/// PR card's Review button; the back arrow returns to the list.
struct PRReviewScreen: View {
    @State private var vm: PRReviewViewModel
    private let highlighter: CodeHighlighter
    var onBack: () -> Void
    var onApprove: (PRReviewApproveContext) -> Void

    init(
        row: PRRow,
        loadFiles: @escaping (PRRow) async throws -> [PRFileChange],
        accountsProvider: @escaping () async -> [GitHubAccount],
        highlighter: CodeHighlighter = SplashCodeHighlighter(),
        onBack: @escaping () -> Void = {},
        onApprove: @escaping (PRReviewApproveContext) -> Void = { _ in }
    ) {
        _vm = State(initialValue: PRReviewViewModel(
            row: row, loadFiles: loadFiles, accountsProvider: accountsProvider))
        self.highlighter = highlighter
        self.onBack = onBack
        self.onApprove = onApprove
    }

    private var pr: PullRequest { vm.row.pr }
    private var repo: Repository { vm.row.repo }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AerieColor.glassLine)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await vm.load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            backButton
            VStack(alignment: .leading, spacing: 6) {
                Text("\(repo.name) · #\(pr.number) · \(pr.authorLogin)\(pr.isMine ? " · yours" : "")")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                Text(pr.title)
                    .aerieFont(AerieFont.sectionTitle())
                    .foregroundStyle(AerieColor.text1)
                    .fixedSize(horizontal: false, vertical: true)
                statusRow
            }
            Spacer(minLength: 16)
            ApproveButton(
                row: vm.row,
                resolution: vm.resolution,
                onApprove: onApprove
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AerieColor.text2)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AerieColor.glass2))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back to pull requests")
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            CIChip(state: pr.ciState)
            ReviewChip(state: pr.reviewState)
            if let add = pr.additions, let del = pr.deletions, let files = pr.changedFiles {
                HStack(spacing: 5) {
                    Text("+\(add)").foregroundStyle(AerieColor.ok)
                    Text("-\(del)").foregroundStyle(AerieColor.err)
                    Text("· \(files) \(files == 1 ? "file" : "files")").foregroundStyle(AerieColor.text3)
                }
                .aerieFont(AerieFont.code(12))
            }
        }
        .padding(.top, 2)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            centered { ProgressView().controlSize(.large) }
        case .empty:
            centered {
                Text("No file changes in this pull request.")
                    .aerieFont(AerieFont.body())
                    .foregroundStyle(AerieColor.text3)
            }
        case .error(let message):
            centered { errorView(message) }
        case .ready(let files):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(files) { file in
                        DiffFileSection(file: file, highlighter: highlighter)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text("Couldn't load the diff")
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text1)
            Text(message)
                .aerieFont(AerieFont.custom(.sans, size: 12.5))
                .foregroundStyle(AerieColor.text3)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AerieColor.glass2))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
                .foregroundStyle(AerieColor.text1)
                .aerieFont(AerieFont.custom(.sans, size: 12.5))
        }
        .frame(maxWidth: 420)
    }

    private func centered<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The primary Approve affordance in the review header. Three states: already
/// approved (green, inert), approvable (amber CTA), and blocked because no
/// non-author account is configured (disabled, with a reason on hover).
private struct ApproveButton: View {
    let row: PRRow
    let resolution: ApproverResolution
    let onApprove: (PRReviewApproveContext) -> Void

    var body: some View {
        if row.pr.reviewState == .approved {
            label("Approved", system: "checkmark.seal.fill", fg: AerieColor.ok, bg: AerieColor.ok.opacity(0.14), line: AerieColor.ok.opacity(0.32))
                .help(row.pr.approvedBy.map { "Approved by \($0)" } ?? "Already approved")
        } else if resolution.canApprove {
            Button { onApprove(PRReviewApproveContext(row: row, resolution: resolution)) } label: {
                label("Approve", system: "checkmark", fg: AerieColor.amberInk, bg: AerieColor.amberFillBot, line: AerieColor.amberCtaLine)
            }
            .buttonStyle(.plain)
            .help("Approve as \(resolution.defaultApprover?.login ?? "")")
        } else {
            label("Approve", system: "checkmark", fg: AerieColor.text3, bg: AerieColor.glass2, line: AerieColor.glassLine)
                .opacity(0.6)
                .help("You can't approve your own PR, and no other account is configured to approve it.")
        }
    }

    private func label(_ text: String, system: String, fg: Color, bg: Color, line: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: system).font(.system(size: 12, weight: .semibold))
            Text(text).aerieFont(AerieFont.custom(.sans, size: 13).weight(.semibold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
