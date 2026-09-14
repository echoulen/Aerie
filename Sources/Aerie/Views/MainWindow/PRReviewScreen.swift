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
            Rectangle().fill(AerieColor.glassLine).frame(height: 1)
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
                isDraft: pr.isDraftPR,
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
                .frame(width: 30, height: 30)
                .contentShape(HudKeyShape(cut: 6))
        }
        .buttonStyle(ReviewIconKeyStyle())
        .help("Back to pull requests")
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            if pr.isDraftPR {
                StatusPill(text: "Draft", tone: .muted)
            }
            CIChip(state: pr.ciState)
            ReviewChip(state: pr.reviewState)
            if let add = pr.additions, let del = pr.deletions, let files = pr.changedFiles {
                HStack(spacing: 5) {
                    Text("+\(add)").foregroundStyle(AerieColor.ok)
                    Text("-\(del)").foregroundStyle(AerieColor.crimsonHot)
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
            // Fetching the diff is a running process → the arc-reactor loader.
            centered { ArcRing(size: 34) }
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
                .buttonStyle(.hud(.standard))
        }
        .frame(maxWidth: 420)
    }

    private func centered<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The review header's square icon key (the back arrow): a 30×30 glass
/// bevelled key that picks up a gold rim + glyph on hover.
private struct ReviewIconKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ReviewIconKey(configuration: configuration)
    }

    private struct ReviewIconKey: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        private let shape = HudKeyShape(cut: 6)

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? AerieColor.amber : AerieColor.text2)
                .background(shape.fill(hovering ? AerieColor.glass3 : AerieColor.glass2))
                .overlay(shape.strokeBorder(hovering ? AerieColor.amberLine : AerieColor.glassLine2, lineWidth: 1))
                .offset(y: configuration.isPressed ? 0.5 : 0)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// The primary Approve affordance in the review header. Four states: already
/// approved (green, inert), approvable (hot-gold `.btn.amber` CTA), approving
/// (arc-cyan running key), and blocked because no non-author account is
/// configured (dimmed glass key with a lock, with a reason on hover).
private struct ApproveButton: View {
    let row: PRRow
    let resolution: ApproverResolution
    let actionStore: PRActionStore
    var onApproveConfirmed: (PRRow, GitHubAccount, String?) async -> String? = { _, _, _ in nil }

    @State private var showConfirm = false
    @State private var justApproved = false

    private var isApproving: Bool { actionStore.isRunning(.approve, for: row) }

    private static let shape = HudKeyShape(cut: 9)

    var body: some View {
        if row.pr.reviewState == .approved || justApproved {
            staticKey("Approved", system: "checkmark.seal.fill",
                      fg: AerieColor.ok, bg: AerieColor.ok.opacity(0.14), line: AerieColor.ok.opacity(0.40),
                      glow: AerieColor.ok.opacity(0.30))
                .help(row.pr.approvedBy.map { "Approved by \($0)" } ?? "Approved")
        } else if resolution.canApprove {
            Button {
                guard !isApproving else { return }
                showConfirm = true
            } label: {
                HStack(spacing: 7) {
                    if isApproving {
                        CardArcSpinner(size: 12)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                    }
                    Text(isApproving ? "Approving…" : "Approve")
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
            }
            // A running approve stays enabled (the guard ignores taps) so the
            // arc key isn't dimmed by the disabled treatment.
            .buttonStyle(.hud(isApproving ? .arc : .amber))
            .help("Approve as \(resolution.defaultApprover?.login ?? "")")
            .popover(isPresented: $showConfirm) {
                DialogApprove(
                    context: PRReviewApproveContext(row: row, resolution: resolution),
                    onConfirm: { approver, comment in
                        showConfirm = false
                        actionStore.start(.approve, row: row) {
                            let error = await onApproveConfirmed(row, approver, comment)
                            if error == nil {
                                await MainActor.run { justApproved = true }
                            }
                            return error
                        }
                    },
                    onCancel: { showConfirm = false }
                )
            }
        } else {
            staticKey("Approve", system: "lock",
                      fg: AerieColor.text3, bg: AerieColor.glass2, line: AerieColor.glassLine, glow: .clear)
                .opacity(0.6)
                .help("You can't approve your own PR, and no other account is configured to approve it.")
        }
    }

    /// A non-interactive key in the Approve slot (approved / blocked).
    private func staticKey(_ text: String, system: String, fg: Color, bg: Color, line: Color, glow: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: system).font(.system(size: 12, weight: .semibold))
            Text(text)
                .aerieFont(AerieFont.custom(.sans, size: 12.5).weight(.bold))
                .tracking(1.0)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Self.shape.fill(bg))
        .overlay(Self.shape.strokeBorder(line, lineWidth: 1))
        .shadow(color: glow, radius: glow == .clear ? 0 : 8)
        .contentShape(Self.shape)
    }
}

/// "AI Review" affordance: a split bevelled key. The primary region triggers the
/// review (auto-approving as the currently-selected account); when more than one
/// account is eligible, a trailing `⌄` opens a menu to pick which one acts. With
/// a single eligible account it degrades to a plain one-tap key. While a review
/// runs the whole key turns arc cyan with a spinner (and hides the picker).
private struct AIReviewButton: View {
    let phase: AIReviewPhase
    /// Draft PRs aren't ready to be reviewed, so the button is held back the
    /// same way it is when no account may approve.
    let isDraft: Bool
    let resolution: ApproverResolution
    /// The user's per-repo pick, or nil to fall back to the resolved default.
    let selectedApproverId: UUID?
    let onSelectApprover: (UUID) -> Void
    let onStart: () -> Void

    @State private var hovering = false

    private static let shape = HudKeyShape(cut: 9)

    private var isRunning: Bool { if case .running = phase { return true }; return false }
    private var canApprove: Bool { resolution.canApprove }
    private var isBlocked: Bool { !canApprove || isDraft }
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
            .disabled(isRunning || !canApprove || isDraft)
            .help(helpText)

            if showsPicker {
                // Fixed height: a width-only frame leaves the Rectangle greedy
                // in the vertical axis, which inflates the header's ideal height
                // and balloons the whole key.
                Rectangle()
                    .fill(AerieColor.glassLine2)
                    .frame(width: 1, height: 22)
                pickerMenu
            }
        }
        .foregroundStyle(isRunning ? AerieColor.arc : AerieColor.text1)
        .background(Self.shape.fill(fill))
        .overlay(Self.shape.strokeBorder(border, lineWidth: 1))
        .shadow(color: glow, radius: glow == .clear ? 0 : 9)
        .opacity(isBlocked && !isRunning ? 0.45 : 1)
        .contentShape(Self.shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
    }

    private var lit: Bool { hovering && !isRunning && !isBlocked }

    private var fill: Color {
        if isRunning { return AerieColor.arc.opacity(0.13) }
        return lit ? AerieColor.glass3 : AerieColor.glass2
    }

    private var border: Color {
        if isRunning { return AerieColor.arcLine }
        return lit ? AerieColor.amberLine : AerieColor.glassLine2
    }

    private var glow: Color {
        if isRunning { return AerieColor.arcGlow.opacity(0.30) }
        return lit ? AerieColor.amberGlow.opacity(0.35) : .clear
    }

    private var helpText: String {
        if isDraft { return "This PR is still a draft — mark it ready for review first." }
        if !canApprove { return "No account is eligible to approve this PR, so AI Review is unavailable." }
        return "Review this PR with the Claude CLI; auto-approves when there are no major problems"
    }

    private var primaryLabel: some View {
        HStack(spacing: 7) {
            if isRunning {
                CardArcSpinner(size: 12)
            } else {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
            }
            Text(isRunning ? "Reviewing…" : "AI Review")
                .aerieFont(AerieFont.custom(.sans, size: 12.5).weight(.medium))
                .tracking(0.75)
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

/// A chamfered banner plate for the review screen's AI-review results —
/// `.card` geometry at banner scale with a tone-coloured rim and wash.
private struct ReviewBannerPlate: ViewModifier {
    let line: Color
    let wash: Color

    func body(content: Content) -> some View {
        let shape = HudPlateShape(cut: 12)
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(shape.fill(AerieColor.glass2))
            .background(shape.fill(wash))
            .overlay(shape.strokeBorder(line, lineWidth: 1))
    }
}

/// Result card for a finished AI review: a verdict header, the summary, and any
/// issues. Approve = green; issues_found = gold.
private struct AIReviewCard: View {
    let review: ClaudeReview
    let actedAs: String?

    private var isApprove: Bool { review.verdict == .approve }
    private var tone: Color { isApprove ? AerieColor.ok : AerieColor.amber }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isApprove ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .shadow(color: tone.opacity(0.6), radius: 5)
                Text((isApprove ? "AI Review · Approved" : "AI Review · Issues found").uppercased())
                    .aerieFont(AerieFont.custom(.sans, size: 12).weight(.semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(tone)

            Text(review.summary)
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
                .fixedSize(horizontal: false, vertical: true)

            if !review.issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .top, spacing: 6) {
                            Text("▸").foregroundStyle(AerieColor.amber.opacity(0.8))
                            Text(issue).foregroundStyle(AerieColor.text2)
                        }
                        .aerieFont(AerieFont.custom(.sans, size: 12.5))
                    }
                }
            }

            if let actedAs {
                Text("\(isApprove ? "Approved" : "Requested changes") as \(actedAs)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }
        }
        .modifier(ReviewBannerPlate(
            line: isApprove ? AerieColor.ok.opacity(0.40) : AerieColor.amberLine,
            wash: isApprove ? AerieColor.ok.opacity(0.05) : AerieColor.amber.opacity(0.05)))
    }
}

/// Live, scrollable console of Claude's progress while a review runs — the
/// design's `.console`: a near-black well, mono 11pt arc-cyan lines, and a
/// blinking `.caret` after the newest line. Auto-scrolls to the newest line.
/// Replaces the old single-line running card.
private struct AIReviewConsole: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArcRing(size: 22)
                Text("Reviewing with Claude…".uppercased())
                    .aerieFont(AerieFont.custom(.sans, size: 12).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AerieColor.arc)
            }
            ProgressSweep(tone: .arc)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .aerieFont(AerieFont.code(11))
                                // Older lines recede; the newest reads brightest.
                                .foregroundStyle(AerieColor.arc.opacity(i == lines.count - 1 ? 0.95 : 0.62))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                        ConsoleCaret()
                            .id(lines.count)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: AerieMetric.radiusRow, style: .continuous)
                        .fill(Color.black.opacity(0.46))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AerieMetric.radiusRow, style: .continuous)
                        .strokeBorder(AerieColor.arcLine.opacity(0.5), lineWidth: 1)
                )
                .onChange(of: lines) { _, _ in
                    proxy.scrollTo(lines.count, anchor: .bottom)
                }
            }
        }
        .modifier(ReviewBannerPlate(line: AerieColor.arcLine, wash: AerieColor.arc.opacity(0.04)))
    }
}

/// `.caret` — a blinking arc-cyan block cursor at the end of the console.
private struct ConsoleCaret: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(AerieColor.arc)
            .frame(width: 7, height: 13)
            .shadow(color: AerieColor.arcGlow, radius: 4)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

/// Error card when an AI review (or approve) couldn't complete — a crimson plate.
private struct AIReviewFailureCard: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(AerieColor.crimsonHot)
                .shadow(color: AerieColor.crimson.opacity(0.6), radius: 5)
            Text(message)
                .aerieFont(AerieFont.custom(.sans, size: 12.5))
                .foregroundStyle(AerieColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(ReviewBannerPlate(line: AerieColor.crimsonLine, wash: AerieColor.crimsonSoft))
    }
}
