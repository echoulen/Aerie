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

    /// The live row, re-passed on every refresh. `vm.row` is the row the
    /// screen opened with (the `@State` model is built once), so everything
    /// here — header status and the AI Review / Approve actions — reads this.
    let row: PRRow

    init(
        row: PRRow,
        store: AIReviewStore,
        actionStore: PRActionStore,
        loadFiles: @escaping (PRRow) async throws -> [PRFileChange],
        accountsProvider: @escaping () async -> [GitHubAccount],
        lastApproverProvider: @escaping (PRRow) async -> [String] = { _ in [] },
        highlighter: CodeHighlighter = SplashCodeHighlighter(),
        onBack: @escaping () -> Void = {},
        onApproveConfirmed: @escaping (PRRow, GitHubAccount, String?) async -> String? = { _, _, _ in nil }
    ) {
        self.row = row
        _vm = State(initialValue: PRReviewViewModel(
            row: row, loadFiles: loadFiles, accountsProvider: accountsProvider,
            lastApproverProvider: lastApproverProvider))
        self.store = store
        self.actionStore = actionStore
        self.highlighter = highlighter
        self.onBack = onBack
        self.onApproveConfirmed = onApproveConfirmed
    }

    private var pr: PullRequest { row.pr }
    private var repo: Repository { row.repo }
    private var aiPhase: AIReviewPhase { store.phase(for: row) }

    @Environment(\.widthClass) private var widthClass

    /// Page gutter: 28pt, or 18pt in the compact layout (`CompactReview`).
    private var gutter: CGFloat { widthClass == .compact ? 18 : 28 }

    var body: some View {
        VStack(spacing: 0) {
            if widthClass == .compact {
                compactHeader
            } else {
                header
            }
            HudRail()
            aiReviewBanner
            approveFailureBanner
            content
            if widthClass == .compact {
                compactActionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await vm.load() }
    }

    /// AI Review can (re)start only when some account may approve and the PR
    /// isn't a draft — the same gate as the header's AI Review button.
    private var canStartAIReview: Bool { vm.resolution.canApprove && !pr.isDraftPR }

    @ViewBuilder
    private var aiReviewBanner: some View {
        switch aiPhase {
        case .idle:
            EmptyView()
        case .running(let lines):
            AIReviewConsole(lines: lines, onStop: { store.stop(row: row) })
                .padding(.horizontal, gutter).padding(.top, widthClass == .compact ? 12 : 16)
        case .done(let review, let actedAs):
            AIReviewCard(review: review, actedAs: actedAs)
                .padding(.horizontal, gutter).padding(.top, widthClass == .compact ? 12 : 16)
        case .failed(let message):
            AIReviewFailureCard(
                title: "AI Review failed",
                message: message,
                onRetry: canStartAIReview ? { store.start(row: row) } : nil)
                .padding(.horizontal, gutter).padding(.top, widthClass == .compact ? 12 : 16)
        }
    }

    @ViewBuilder
    private var approveFailureBanner: some View {
        // `message` already reads "Approve failed: …" (the
        // `onApproveConfirmed` closure's error string) — display it as-is.
        if case .failed(let message) = actionStore.phase(.approve, for: row) {
            AIReviewFailureCard(
                title: "Approve failed",
                message: message,
                onRetry: { actionStore.retry(.approve, row: row) })
                .padding(.horizontal, gutter).padding(.top, widthClass == .compact ? 12 : 16)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            backButton
            VStack(alignment: .leading, spacing: 8) {
                Text("\(repo.name) · #\(pr.number) · \(pr.authorLogin)\(pr.isMine ? " · yours" : "")")
                    .aerieFont(AerieFont.code(11))
                    .tracking(1.1) // 0.10em @ 11px
                    .foregroundStyle(AerieColor.text4)
                Text(pr.title)
                    .aerieFont(AerieFont.custom(.sans, size: 22).weight(.semibold))
                    .tracking(0.11)
                    .foregroundStyle(AerieColor.text1)
                    .shadow(color: AerieColor.amber.opacity(0.22), radius: 14)
                    .fixedSize(horizontal: false, vertical: true)
                statusRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top, spacing: 10) {
                aiReviewButton()
                approveButton()
            }
            .fixedSize()
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private func aiReviewButton(fills: Bool = false) -> some View {
        AIReviewButton(
            phase: aiPhase,
            isDraft: pr.isDraftPR,
            resolution: vm.resolution,
            selectedApproverId: store.selectedApproverId(for: row),
            onSelectApprover: { store.selectApprover($0, for: row) },
            onStart: { store.start(row: row) },
            fills: fills
        )
    }

    private func approveButton(fills: Bool = false) -> some View {
        ApproveButton(
            row: row,
            resolution: vm.resolution,
            actionStore: actionStore,
            onApproveConfirmed: onApproveConfirmed,
            fills: fills
        )
    }

    // MARK: Compact layout (`compact.jsx` `CompactReview`)

    /// Back key · repo · #N · CI tag, then the wrapped title and the diff size.
    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                backButton
                Text("\(repo.name) · #\(pr.number)")
                    .aerieFont(AerieFont.code(10.5))
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
                if pr.isDraftPR { MiniPill(text: "draft", tone: .muted) }
                Spacer(minLength: 8)
                compactCITag
            }
            Text(pr.title)
                .aerieFont(AerieFont.custom(.sans, size: 16).weight(.semibold))
                .lineSpacing(4)                          // lh 1.35
                .foregroundStyle(AerieColor.text1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            if let add = pr.additions, let del = pr.deletions, let files = pr.changedFiles {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Text("+\(add)").foregroundStyle(AerieColor.ok)
                        Text("−\(del)").foregroundStyle(AerieColor.crimsonHot)
                    }
                    Text("\(files) \(files == 1 ? "file" : "files")")
                        .foregroundStyle(AerieColor.text3)
                }
                .aerieFont(AerieFont.code(11))
                .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// `pill ok` with a 5pt dot and just "CI", toned by the check state.
    private var compactCITag: some View {
        let tone: StatusPill.Tone = {
            switch pr.ciState {
            case .success: return .ok
            case .failure: return .err
            case .pending: return .warn
            case .none:    return .muted
            }
        }()
        return HStack(spacing: 5) {
            StatusDot(tone: tone).scaleEffect(5.0 / 7.0)
            MiniPill(text: "CI", tone: tone)
        }
        .fixedSize()
    }

    /// The primary actions move to a bar pinned under the diff.
    private var compactActionBar: some View {
        HStack(spacing: 9) {
            aiReviewButton(fills: true)
            approveButton(fills: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.42))
        .overlay(alignment: .top) {
            Rectangle().fill(AerieColor.glassLine).frame(height: 1)
        }
    }

    /// `RvBack` — a 32×32 `.btn.ghost.sm` key with a glass hairline inset.
    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 32, height: 32)
                .contentShape(HudKeyShape(cut: 6))
        }
        .buttonStyle(ReviewBackKeyStyle())
        .help("Back to pull requests")
    }

    // Wraps (and the branch note truncates) so a long branch name can't push
    // the header — and with it the whole screen — wider than the window.
    private var statusRow: some View {
        FlowLayout(itemSpacing: 10, rowSpacing: 8) {
            if pr.isDraftPR {
                StatusPill(text: "Draft", tone: .muted)
            }
            CIChip(state: pr.ciState)
            ReviewChip(state: pr.reviewState)
            if pr.awaitingReReview {
                StatusPill(text: "Responded · re-review", tone: .amber)
            }
            if let add = pr.additions, let del = pr.deletions, let files = pr.changedFiles {
                HStack(spacing: 5) {
                    Text("+\(add)").foregroundStyle(AerieColor.ok)
                    Text("−\(del)").foregroundStyle(AerieColor.crimsonHot)
                    Text("· \(files) \(files == 1 ? "file" : "files")").foregroundStyle(AerieColor.text3)
                }
                .aerieFont(AerieFont.code(11.5))
                .fixedSize()
            }
            HudNote(text: "head \(pr.sourceBranch)", truncates: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            centered {
                VStack(spacing: 14) {
                    ArcRing(size: 40)
                    HudNote(text: "loading unified diff")
                }
            }
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
                LazyVStack(alignment: .leading, spacing: widthClass == .compact ? 10 : 12) {
                    ForEach(files) { file in
                        DiffFileSection(file: file, highlighter: highlighter)
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.top, widthClass == .compact ? 12 : 18)
                .padding(.bottom, widthClass == .compact ? 16 : 24)
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

/// `RvBack`: `.btn.ghost.sm` geometry with the design's inline glass-line inset
/// (which also pins the rim on hover); hover lifts to glass-2 / text-1.
private struct ReviewBackKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ReviewBackKey(configuration: configuration)
    }

    private struct ReviewBackKey: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        private let shape = HudKeyShape(cut: 6)

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? AerieColor.text1 : AerieColor.text3)
                .background(shape.fill(hovering ? AerieColor.glass2 : Color.clear))
                .overlay(shape.strokeBorder(AerieColor.glassLine, lineWidth: 1))
                .offset(y: configuration.isPressed ? 0.5 : 0)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// The primary Approve affordance in the review header (`review.jsx`
/// `ApproveButton`). States: already approved (ok-tinted cut-9 block,
/// "APPROVED"), approvable (`.btn.amber`, "APPROVE"), approving (arc running
/// key), and blocked because no non-author account is configured (glass-2,
/// text-4, 0.7 opacity, with a reason on hover).
private struct ApproveButton: View {
    let row: PRRow
    let resolution: ApproverResolution
    let actionStore: PRActionStore
    var onApproveConfirmed: (PRRow, GitHubAccount, String?) async -> String? = { _, _, _ in nil }
    /// Stretch to the available width (the compact bottom bar).
    var fills: Bool = false

    @State private var showConfirm = false
    @State private var justApproved = false

    private var isApproving: Bool { actionStore.isRunning(.approve, for: row) }

    private static let shape = HudKeyShape(cut: 9)

    var body: some View {
        if row.pr.reviewState == .approved || justApproved {
            staticKey("APPROVED", weight: .bold,
                      fg: AerieColor.ok, bg: AerieColor.ok.opacity(0.14), line: AerieColor.ok.opacity(0.40),
                      glow: AerieColor.ok.opacity(0.35))
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
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    }
                    Text(isApproving ? "APPROVING…" : "APPROVE")
                }
                .frame(maxWidth: fills ? .infinity : nil)
                // `.btn.amber` with `padding: 9px 20px` (style supplies 8×15).
                .padding(.horizontal, 5)
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
            staticKey("APPROVE", weight: .semibold,
                      fg: AerieColor.text4, bg: AerieColor.glass2, line: AerieColor.glassLine, glow: .clear)
                .opacity(0.7)
                .help("You can't approve your own PR, and no other account is configured to approve it.")
        }
    }

    /// A non-interactive cut-9 block in the Approve slot (approved / blocked).
    private func staticKey(_ text: String, weight: Font.Weight, fg: Color, bg: Color, line: Color, glow: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
            Text(text)
                .aerieFont(AerieFont.custom(.sans, size: 12.5).weight(weight))
                .tracking(1.0) // 0.08em @ 12.5px
        }
        .frame(maxWidth: fills ? .infinity : nil)
        .foregroundStyle(fg)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Self.shape.fill(bg))
        .overlay(Self.shape.strokeBorder(line, lineWidth: 1))
        .shadow(color: glow, radius: glow == .clear ? 0 : 8)
        .contentShape(Self.shape)
    }
}

/// "AI Review" affordance (`review.jsx` `AIReviewButton`): a split cut-9 key on
/// glass-2 with a glass-line-2 rim. The primary region triggers the review
/// (auto-approving as the currently-selected account); when more than one
/// account is eligible, a trailing `⌄` segment opens a menu to pick which one
/// acts. With a single eligible account it degrades to a plain one-tap key.
/// While a review runs the rim and text turn arc cyan with a spinner and the
/// picker segment is hidden.
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
    /// Stretch to the available width (the compact bottom bar).
    var fills: Bool = false

    private static let shape = HudKeyShape(cut: 9)

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
                    .frame(maxWidth: fills ? .infinity : nil)
                    .padding(.horizontal, 16)
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
        .background(Self.shape.fill(AerieColor.glass2))
        .overlay(Self.shape.strokeBorder(isRunning ? AerieColor.arcLine : AerieColor.glassLine2, lineWidth: 1))
        .contentShape(Self.shape)
    }

    private var helpText: String {
        if isDraft { return "This PR is still a draft — mark it ready for review first." }
        if !canApprove { return "No account is eligible to approve this PR, so AI Review is unavailable." }
        return "Review this PR with the Claude CLI; auto-approves when there are no major problems"
    }

    private var primaryLabel: some View {
        HStack(spacing: 8) {
            if isRunning {
                CardArcSpinner(size: 13)
            } else {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
            }
            Text(isRunning ? "REVIEWING…" : "AI REVIEW")
                .aerieFont(AerieFont.custom(.sans, size: 12.5).weight(.semibold))
                .tracking(0.88) // 0.07em @ 12.5px
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

/// A review-screen banner on a MARK III `.card` plate (16pt padding), with an
/// optional tone rim + glow (the design's inline inset `box-shadow`), wash,
/// and `.hud-corners` brackets.
private struct ReviewBannerCard: ViewModifier {
    var line: Color? = nil
    var glow: Color = .clear
    var wash: Color = .clear
    var corners: Bool = true

    func body(content: Content) -> some View {
        let shape = HudPlateShape(cut: AerieMetric.cutCard)
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(wash)
            .glass(.card)
            .overlay {
                if let line {
                    shape.strokeBorder(line, lineWidth: 1).allowsHitTesting(false)
                }
            }
            .overlay {
                if corners { HudCorners() }
            }
            .shadow(color: glow, radius: glow == .clear ? 0 : 12)
    }
}

/// Result card for a finished AI review (`AIVerdictCard`): tone header +
/// "verdict locked" note, the summary, numbered issues, and the acting account.
/// Approve = green; issues_found = gold.
private struct AIReviewCard: View {
    let review: ClaudeReview
    let actedAs: String?

    private var isApprove: Bool { review.verdict == .approve }
    private var tone: Color { isApprove ? AerieColor.ok : AerieColor.amber }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Group {
                    if isApprove {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    } else {
                        Text("▲").aerieFont(AerieFont.custom(.sans, size: 13))
                    }
                }
                Text((isApprove ? "AI Review · Approved" : "AI Review · Issues found").uppercased())
                    .aerieFont(AerieFont.custom(.sans, size: 12.5).weight(.bold))
                    .tracking(1.25) // 0.10em @ 12.5px
                Spacer(minLength: 8)
                HudNote(text: "verdict locked")
            }
            .foregroundStyle(tone)

            Text(review.summary)
                .aerieFont(AerieFont.body())
                .lineSpacing(5)
                .foregroundStyle(AerieColor.text2)
                .frame(maxWidth: 840, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if !review.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(review.issues.enumerated()), id: \.offset) { i, issue in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text(String(format: "%02d", i + 1))
                                .aerieFont(AerieFont.code(11))
                                .foregroundStyle(tone)
                            Text(issue)
                                .aerieFont(AerieFont.custom(.sans, size: 12.5))
                                .lineSpacing(4)
                                .foregroundStyle(AerieColor.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 12)
            }

            if let actedAs {
                Text("\(isApprove ? "approved" : "requested changes") as \(actedAs)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                    .padding(.top, 14)
            }
        }
        .modifier(ReviewBannerCard(
            line: isApprove ? AerieColor.ok.opacity(0.35) : AerieColor.amberLine,
            glow: isApprove ? AerieColor.ok.opacity(0.30) : AerieColor.amberGlow.opacity(0.30)))
    }
}

/// Live console card while a review runs (`AIConsole`): arc ring, uppercase arc
/// title with a "streaming · N lines" note, a live `claude cli` pill, then the
/// `.console` well (max 150pt) streaming Claude's progress with a caret.
private struct AIReviewConsole: View {
    let lines: [String]
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ArcRing(size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reviewing with Claude".uppercased())
                        .aerieFont(AerieFont.custom(.sans, size: 12.5).weight(.semibold))
                        .tracking(1.0) // 0.08em @ 12.5px
                        .foregroundStyle(AerieColor.arc)
                    HudNote(text: "streaming · \(lines.count) line\(lines.count == 1 ? "" : "s")")
                }
                Spacer(minLength: 8)
                LiveArcPill(text: "claude cli")
                Button(action: onStop) {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold))
                        Text("Stop")
                    }
                }
                .buttonStyle(.hud(.danger, size: .small))
                .help("Stop this AI Review — nothing is posted to the PR")
            }
            CardConsole(lines: lines, maxHeight: 150)
        }
        .modifier(ReviewBannerCard())
    }
}

/// `pill arc` led by a pulsing `dot arc live`.
private struct LiveArcPill: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            BreathingDot(
                style: .init(color: AerieColor.arc, glow: AerieColor.arcGlow, glowRadius: 6),
                animated: !reduceMotion)
                .frame(width: 7, height: 7)
            Text(text.uppercased())
                .aerieFont(AerieFont.custom(.sans, size: 10.5).weight(.semibold))
                .tracking(1.05)
        }
        .foregroundStyle(AerieColor.arc)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).fill(AerieColor.arcSoft))
        .overlay(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).strokeBorder(AerieColor.arcLine, lineWidth: 1))
        .shadow(color: AerieColor.arcGlow.opacity(0.35), radius: 6)
        .fixedSize()
    }
}

/// Error card when an AI review (or approve) couldn't complete
/// (`AIFailureCard`): a crimson-washed `.card` with a crimson rim + glow, ⊗,
/// an uppercase crimson title, the message, and a `.btn.sm` Retry.
private struct AIReviewFailureCard: View {
    let title: String
    let message: String
    /// Nil hides Retry (e.g. AI Review can't currently start).
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("⊗")
                .aerieFont(AerieFont.custom(.sans, size: 14))
                .foregroundStyle(AerieColor.crimsonHot)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .aerieFont(AerieFont.custom(.sans, size: 12).weight(.bold))
                    .tracking(1.2) // 0.10em @ 12px
                    .foregroundStyle(AerieColor.crimsonHot)
                Text(message)
                    .aerieFont(AerieFont.custom(.sans, size: 12.5))
                    .lineSpacing(4)
                    .foregroundStyle(AerieColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.hud(.standard, size: .small))
                    .fixedSize()
            }
        }
        .modifier(ReviewBannerCard(
            line: AerieColor.crimsonLine,
            glow: AerieColor.crimson.opacity(0.35),
            wash: AerieColor.crimsonSoft,
            corners: false))
    }
}
