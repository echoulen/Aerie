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
    let store: AIReviewStore
    private let highlighter: CodeHighlighter
    var onBack: () -> Void
    var onApprove: (PRReviewApproveContext) -> Void

    init(
        row: PRRow,
        store: AIReviewStore,
        loadFiles: @escaping (PRRow) async throws -> [PRFileChange],
        accountsProvider: @escaping () async -> [GitHubAccount],
        highlighter: CodeHighlighter = SplashCodeHighlighter(),
        onBack: @escaping () -> Void = {},
        onApprove: @escaping (PRReviewApproveContext) -> Void = { _ in }
    ) {
        _vm = State(initialValue: PRReviewViewModel(
            row: row, loadFiles: loadFiles, accountsProvider: accountsProvider))
        self.store = store
        self.highlighter = highlighter
        self.onBack = onBack
        self.onApprove = onApprove
    }

    private var pr: PullRequest { vm.row.pr }
    private var repo: Repository { vm.row.repo }
    private var aiPhase: AIReviewPhase { store.phase(for: pr.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AerieColor.glassLine)
            aiReviewBanner
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await vm.load() }
    }

    @ViewBuilder
    private var aiReviewBanner: some View {
        switch aiPhase {
        case .idle:
            EmptyView()
        case .running(let lines):
            AIReviewConsole(lines: lines)
                .padding(.horizontal, 28).padding(.top, 16)
        case .done(let review, let actedAs):
            AIReviewCard(review: review, actedAs: actedAs)
                .padding(.horizontal, 28).padding(.top, 16)
        case .failed(let message):
            AIReviewFailureCard(message: message)
                .padding(.horizontal, 28).padding(.top, 16)
        }
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
            AIReviewButton(
                phase: aiPhase,
                canApprove: vm.resolution.canApprove,
                action: { store.start(row: vm.row) }
            )
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

/// "AI Review" affordance: triggers `runAIReview()`, shows a spinner while it
/// runs. Styled like the other glass header buttons.
private struct AIReviewButton: View {
    let phase: AIReviewPhase
    let canApprove: Bool
    let action: () -> Void

    private var isRunning: Bool { if case .running = phase { return true }; return false }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                }
                Text(isRunning ? "Reviewing…" : "AI Review")
                    .aerieFont(AerieFont.custom(.sans, size: 13).weight(.semibold))
            }
            .foregroundStyle(AerieColor.text1)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AerieColor.glass2))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRunning || !canApprove)
        .help(canApprove
            ? "Review this PR with the Claude CLI; auto-approves when there are no major problems"
            : "No account is eligible to approve this PR, so AI Review is unavailable.")
    }
}

/// Result card for a finished AI review: a verdict pill, the summary, and any
/// issues. Approve = green; issues_found = amber.
private struct AIReviewCard: View {
    let review: ClaudeReview
    let actedAs: String?

    private var isApprove: Bool { review.verdict == .approve }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isApprove ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                Text(isApprove ? "AI Review · Approved" : "AI Review · Issues found")
                    .aerieFont(AerieFont.custom(.sans, size: 13).weight(.semibold))
            }
            .foregroundStyle(isApprove ? AerieColor.ok : AerieColor.amberInk)

            Text(review.summary)
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
                .fixedSize(horizontal: false, vertical: true)

            if !review.issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(AerieColor.text3)
                            Text(issue).foregroundStyle(AerieColor.text2)
                        }
                        .aerieFont(AerieFont.custom(.sans, size: 12.5))
                    }
                }
            }

            if let actedAs {
                Text("\(isApprove ? "Approved" : "Commented") as \(actedAs)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AerieColor.glass2))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isApprove ? AerieColor.ok.opacity(0.32) : AerieColor.amberCtaLine, lineWidth: 1))
    }
}

/// Live, scrollable console of Claude's progress while a review runs. Auto-scrolls
/// to the newest line. Replaces the old single-line running card.
private struct AIReviewConsole: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reviewing with Claude…")
                    .aerieFont(AerieFont.custom(.sans, size: 12.5).weight(.semibold))
                    .foregroundStyle(AerieColor.text2)
            }
            if !lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .aerieFont(AerieFont.code(11))
                                    .foregroundStyle(AerieColor.text3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: lines.count) { _, _ in
                        if let last = lines.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AerieColor.glass2))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }
}

/// Error card when an AI review couldn't complete.
private struct AIReviewFailureCard: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(AerieColor.err)
            Text(message)
                .aerieFont(AerieFont.custom(.sans, size: 12.5))
                .foregroundStyle(AerieColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AerieColor.glass2))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(AerieColor.err.opacity(0.3), lineWidth: 1))
    }
}
