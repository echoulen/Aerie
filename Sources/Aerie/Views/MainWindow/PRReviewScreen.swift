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
    let actionStore: PRActionStore
    private let highlighter: CodeHighlighter
    var onBack: () -> Void
    /// Runs the actual approve (the old `approveDialog`'s `onConfirm` body).
    /// Returns an error message on failure, nil on success.
    var onApproveConfirmed: (PRRow, GitHubAccount, String?) async -> String? = { _, _, _ in nil }

    init(
        row: PRRow,
        store: AIReviewStore,
        actionStore: PRActionStore,
        loadFiles: @escaping (PRRow) async throws -> [PRFileChange],
        accountsProvider: @escaping () async -> [GitHubAccount],
        lastApproverProvider: @escaping (UUID) async -> String? = { _ in nil },
        highlighter: CodeHighlighter = SplashCodeHighlighter(),
        onBack: @escaping () -> Void = {},
        onApproveConfirmed: @escaping (PRRow, GitHubAccount, String?) async -> String? = { _, _, _ in nil }
    ) {
        _vm = State(initialValue: PRReviewViewModel(
            row: row, loadFiles: loadFiles, accountsProvider: accountsProvider,
            lastApproverProvider: lastApproverProvider))
        self.store = store
        self.actionStore = actionStore
        self.highlighter = highlighter
        self.onBack = onBack
        self.onApproveConfirmed = onApproveConfirmed
    }

    private var pr: PullRequest { vm.row.pr }
    private var repo: Repository { vm.row.repo }
    private var aiPhase: AIReviewPhase { store.phase(for: vm.row) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AerieColor.glassLine)
            aiReviewBanner
            approveFailureBanner
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

    @ViewBuilder
    private var approveFailureBanner: some View {
        // `message` already reads "Approve failed: …" (the
        // `onApproveConfirmed` closure's error string) — display it as-is.
        if case .failed(let message) = actionStore.phase(.approve, for: vm.row) {
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
                resolution: vm.resolution,
                selectedApproverId: store.selectedApproverId(for: vm.row),
                onSelectApprover: { store.selectApprover($0, for: vm.row) },
                onStart: { store.start(row: vm.row) }
            )
            ApproveButton(
                row: vm.row,
                resolution: vm.resolution,
                actionStore: actionStore,
                onApproveConfirmed: onApproveConfirmed
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
    let actionStore: PRActionStore
    var onApproveConfirmed: (PRRow, GitHubAccount, String?) async -> String? = { _, _, _ in nil }

    @State private var showConfirm = false

    private var isApproving: Bool { actionStore.isRunning(.approve, for: row) }

    var body: some View {
        if row.pr.reviewState == .approved {
            label("Approved", system: "checkmark.seal.fill", fg: AerieColor.ok, bg: AerieColor.ok.opacity(0.14), line: AerieColor.ok.opacity(0.32))
                .help(row.pr.approvedBy.map { "Approved by \($0)" } ?? "Already approved")
        } else if resolution.canApprove {
            Button {
                guard !isApproving else { return }
                showConfirm = true
            } label: {
                if isApproving {
                    label("Approving…", system: "", fg: AerieColor.amberInk, bg: AerieColor.amberFillBot, line: AerieColor.amberCtaLine, spinner: true)
                } else {
                    label("Approve", system: "checkmark", fg: AerieColor.amberInk, bg: AerieColor.amberFillBot, line: AerieColor.amberCtaLine)
                }
            }
            .buttonStyle(.plain)
            .disabled(isApproving)
            .help("Approve as \(resolution.defaultApprover?.login ?? "")")
            .popover(isPresented: $showConfirm) {
                DialogApprove(
                    context: PRReviewApproveContext(row: row, resolution: resolution),
                    onConfirm: { approver, comment in
                        showConfirm = false
                        actionStore.start(.approve, row: row) {
                            await onApproveConfirmed(row, approver, comment)
                        }
                    },
                    onCancel: { showConfirm = false }
                )
            }
        } else {
            label("Approve", system: "checkmark", fg: AerieColor.text3, bg: AerieColor.glass2, line: AerieColor.glassLine)
                .opacity(0.6)
                .help("You can't approve your own PR, and no other account is configured to approve it.")
        }
    }

    private func label(_ text: String, system: String, fg: Color, bg: Color, line: Color, spinner: Bool = false) -> some View {
        HStack(spacing: 7) {
            if spinner {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: system).font(.system(size: 12, weight: .semibold))
            }
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

/// "AI Review" affordance: a split button. The primary region triggers the
/// review (auto-approving as the currently-selected account); when more than one
/// account is eligible, a trailing `⌄` opens a menu to pick which one acts. With
/// a single eligible account it degrades to a plain one-tap button. Shows a
/// spinner (and hides the picker) while a review runs.
private struct AIReviewButton: View {
    let phase: AIReviewPhase
    let resolution: ApproverResolution
    /// The user's per-repo pick, or nil to fall back to the resolved default.
    let selectedApproverId: UUID?
    let onSelectApprover: (UUID) -> Void
    let onStart: () -> Void

    private var isRunning: Bool { if case .running = phase { return true }; return false }
    private var canApprove: Bool { resolution.canApprove }
    /// Which account the review will act as right now — the basis for the menu
    /// checkmark. Mirrors `AIReviewStore.effectiveApprover`: the pick when still
    /// eligible, else the default.
    private var effectiveApproverId: UUID? {
        if let selectedApproverId,
           resolution.eligible.contains(where: { $0.id == selectedApproverId }) {
            return selectedApproverId
        }
        return resolution.defaultApprover?.id
    }
    private var showsPicker: Bool { resolution.needsPicker && !isRunning && canApprove }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onStart) {
                primaryLabel
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRunning || !canApprove)
            .help(canApprove
                ? "Review this PR with the Claude CLI; auto-approves when there are no major problems"
                : "No account is eligible to approve this PR, so AI Review is unavailable.")

            if showsPicker {
                // Fixed height: a width-only frame leaves the Rectangle greedy
                // in the vertical axis, which inflates the header's ideal height
                // and balloons the whole capsule.
                Rectangle()
                    .fill(AerieColor.glassLine)
                    .frame(width: 1, height: 22)
                pickerMenu
            }
        }
        .foregroundStyle(AerieColor.text1)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AerieColor.glass2))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(AerieColor.glassLine, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var primaryLabel: some View {
        HStack(spacing: 7) {
            if isRunning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
            }
            Text(isRunning ? "Reviewing…" : "AI Review")
                .aerieFont(AerieFont.custom(.sans, size: 13).weight(.semibold))
        }
    }

    private var pickerMenu: some View {
        Menu {
            ForEach(resolution.eligible) { acc in
                Button { onSelectApprover(acc.id) } label: {
                    if acc.id == effectiveApproverId {
                        Label("\(acc.login) · \(acc.host)", systemImage: "checkmark")
                    } else {
                        Text("\(acc.login) · \(acc.host)")
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AerieColor.text2)
                .padding(.horizontal, 11)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which account approves as")
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
                    .onChange(of: lines) { _, _ in
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
