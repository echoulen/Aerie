import XCTest
@testable import Aerie

@MainActor
final class AIReviewStoreTests: XCTestCase {
    private let acctId = UUID()
    private func acct(_ login: String = "reviewer") -> GitHubAccount {
        GitHubAccount(id: acctId, login: login, host: "github.com")
    }
    private func repo() -> Repository {
        Repository(id: UUID(), name: "aerie", localPath: URL(fileURLWithPath: "/tmp/aerie"),
                   githubOwner: "echoulen", githubRepo: "aerie", defaultBranch: "main",
                   primaryAccountId: acctId, sortOrder: 0, hidden: false)
    }
    private func prRow(number: Int = 1, repo: Repository? = nil) -> PRRow {
        let pr = PullRequest(id: UUID(), repoId: UUID(), number: number, title: "T",
            authorLogin: "octocat", sourceBranch: "feat/x", isMine: false, state: .open,
            ciState: .success, reviewState: .reviewRequired, labels: [],
            htmlUrl: URL(string: "https://e.com")!, updatedAt: Date(timeIntervalSince1970: 1))
        return PRRow(pr: pr, repo: repo ?? self.repo(), localState: nil)
    }
    private func makeStore(
        files: @escaping (PRRow) async throws -> [PRFileChange] = { _ in [] },
        loadFollowUp: @escaping (PRRow) async throws -> AIReviewFollowUp? = { _ in nil },
        run: @escaping (PRRow, String, AIReviewFollowUp?, @escaping @Sendable (String) -> Void) async -> ClaudeReviewOutcome,
        resolveApprover: @escaping (PRRow) async -> ApproverResolution = { _ in ApproverResolution(eligible: [], defaultApprover: nil) },
        approve: @escaping (PRRow, GitHubAccount, String) async -> String? = { _, _, _ in nil },
        requestChanges: @escaping (PRRow, GitHubAccount, String) async -> String? = { _, _, _ in nil }
    ) -> AIReviewStore {
        AIReviewStore(loadFiles: files, loadFollowUp: loadFollowUp, runReview: run, resolveApprover: resolveApprover,
                      approve: approve, requestChanges: requestChanges)
    }

    /// Convenience: an `ApproverResolution` with `def` as the default and (unless
    /// overridden) the sole eligible account.
    private func resolution(default def: GitHubAccount?, eligible: [GitHubAccount]? = nil) -> ApproverResolution {
        ApproverResolution(eligible: eligible ?? def.map { [$0] } ?? [], defaultApprover: def)
    }

    private func account(_ login: String, id: UUID = UUID()) -> GitHubAccount {
        GitHubAccount(id: id, login: login, host: "github.com")
    }
    private func settle(_ store: AIReviewStore, _ row: PRRow) async {
        for _ in 0..<200 {
            if case .running = store.phase(for: row) { await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000) }
            else if case .idle = store.phase(for: row) { await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000) }
            else { return }
        }
    }

    func test_noApprover_failsWithoutRunning() async {
        var ran = false
        let store = makeStore(run: { _, _, _, _ in ran = true; return .failed("x") }, resolveApprover: { _ in self.resolution(default: nil) })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertFalse(ran)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertTrue(m.contains("approver"))
    }

    func test_approveVerdict_callsApprove_doneWithActedAs() async {
        var approveBody: String?
        let store = makeStore(
            run: { _, _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "LGTM", issues: [], raw: "")) },
            resolveApprover: { _ in self.resolution(default: self.acct("reviewer")) },
            approve: { _, a, b in approveBody = b; XCTAssertEqual(a.login, "reviewer"); return nil })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertTrue(approveBody?.contains("LGTM") == true, "approve body carries Claude's summary")
        XCTAssertTrue(approveBody?.contains("## ✅ AI Review · Approved") == true, "wrapped in the formatted markdown body, not a bare summary")
        guard case .done(let r, let actedAs) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(r.verdict, .approve); XCTAssertEqual(actedAs, "reviewer")
    }

    func test_issuesFound_requestsChanges_notApprove() async {
        var approveCalled = false, requestChangesBody: String?
        let store = makeStore(
            run: { _, _, _, _ in .success(ClaudeReview(verdict: .issuesFound, summary: "bug", issues: ["x"], raw: "")) },
            resolveApprover: { _ in self.resolution(default: self.acct()) },
            approve: { _, _, _ in approveCalled = true; return nil },
            requestChanges: { _, _, b in requestChangesBody = b; return nil })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertFalse(approveCalled)
        XCTAssertTrue(requestChangesBody?.contains("x") == true)
        guard case .done = store.phase(for: row) else { return XCTFail() }
    }

    func test_issuesFound_requestChangesFails_setsFailed() async {
        let store = makeStore(
            run: { _, _, _, _ in .success(ClaudeReview(verdict: .issuesFound, summary: "bug", issues: ["x"], raw: "")) },
            resolveApprover: { _ in self.resolution(default: self.acct()) },
            requestChanges: { _, _, _ in "422 unprocessable" })
        let row = prRow(); store.start(row: row); await settle(store, row)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertTrue(m.contains("422 unprocessable"))
    }

    // MARK: Stop

    /// A one-shot latch the test opens to let a suspended closure continue.
    private actor Gate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if open { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() { open = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
    }

    /// Polls until `condition` holds (or ~1 s passes).
    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func isRunning(_ store: AIReviewStore, _ row: PRRow) -> Bool {
        if case .running = store.phase(for: row) { return true }; return false
    }

    func test_stop_whileReviewing_cancelsTheRun_returnsToIdle_andPostsNothing() async {
        var sawCancellation = false
        var posted = false
        let store = makeStore(
            run: { _, _, _, _ in
                // A long review that honours cancellation, like the real CLI run.
                while !Task.isCancelled { try? await Task.sleep(nanoseconds: 2_000_000) }
                sawCancellation = true
                return .success(ClaudeReview(verdict: .approve, summary: "late", issues: [], raw: ""))
            },
            resolveApprover: { _ in self.resolution(default: self.acct()) },
            approve: { _, _, _ in posted = true; return nil },
            requestChanges: { _, _, _ in posted = true; return nil })
        let row = prRow()
        store.start(row: row)
        await eventually { self.isRunning(store, row) }
        XCTAssertTrue(store.canStop(row: row))

        store.stop(row: row)
        XCTAssertEqual(store.phase(for: row), .idle, "stop is immediate")
        XCTAssertFalse(store.canStop(row: row))
        await eventually { sawCancellation }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(sawCancellation, "the review task is cancelled, which terminates the CLI")
        XCTAssertFalse(posted, "a stopped review never approves or requests changes")
        XCTAssertEqual(store.phase(for: row), .idle, "the cancelled run's result is discarded")
    }

    func test_stop_thenStartAgain_theOldRunDoesNotClobberTheNewOne() async {
        let firstGate = Gate()
        var calls = 0
        let store = makeStore(
            run: { _, _, _, _ in
                calls += 1
                if calls == 1 {
                    await firstGate.wait()   // ignores cancellation, finishes late
                    return .failed("stale")
                }
                return .success(ClaudeReview(verdict: .approve, summary: "fresh", issues: [], raw: ""))
            },
            resolveApprover: { _ in self.resolution(default: self.acct()) })
        let row = prRow()
        store.start(row: row)
        await eventually { calls == 1 }
        store.stop(row: row)
        store.start(row: row)
        await eventually { if case .done = store.phase(for: row) { return true }; return false }
        await firstGate.release()
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard case .done(let review, _) = store.phase(for: row) else { return XCTFail("\(store.phase(for: row))") }
        XCTAssertEqual(review.summary, "fresh", "the stale run finishing later must not overwrite the new result")
        store.start(row: row)   // and the key isn't stuck as running
        await eventually { calls == 3 }
        XCTAssertEqual(calls, 3)
    }

    func test_stop_duringSubmission_isIgnored_soThePostedReviewIsReported() async {
        let postGate = Gate()
        var posts = 0
        let store = makeStore(
            run: { _, _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            resolveApprover: { _ in self.resolution(default: self.acct()) },
            approve: { _, _, _ in posts += 1; await postGate.wait(); return nil })
        let row = prRow()
        store.start(row: row)
        await eventually { posts == 1 }
        XCTAssertFalse(store.canStop(row: row), "once the review is being posted it can't be taken back")
        store.stop(row: row)
        await postGate.release()
        await settle(store, row)
        guard case .done = store.phase(for: row) else { return XCTFail("\(store.phase(for: row))") }
        XCTAssertEqual(posts, 1)
    }

    func test_stop_whenNothingIsRunning_isANoOp() {
        let store = makeStore(run: { _, _, _, _ in .failed("unused") })
        let row = prRow()
        XCTAssertFalse(store.canStop(row: row))
        store.stop(row: row)
        XCTAssertEqual(store.phase(for: row), .idle)
    }

    // MARK: Follow-up

    private func sampleFollowUp() -> AIReviewFollowUp {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        return AIReviewFollowUp(
            previous: .init(author: "reviewer", state: "CHANGES_REQUESTED", body: "<!-- aerie:ai-review -->\n- race",
                            submittedAt: t0, commitOid: "c1"),
            responses: [.init(author: "octocat", body: "main actor only", createdAt: t0.addingTimeInterval(60), kind: .conversation)],
            newCommits: [.init(oid: "c2", headline: "tidy")],
            historyRewritten: false)
    }

    func test_followUp_isPassedToTheReview_andAnnouncedInTheLog() async {
        let expected = sampleFollowUp()
        var received: AIReviewFollowUp?
        let store = makeStore(
            loadFollowUp: { _ in expected },
            run: { _, _, followUp, _ in
                received = followUp
                return .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: ""))
            },
            resolveApprover: { _ in self.resolution(default: self.acct()) })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertEqual(received, expected)
    }

    func test_followUpFetchFails_failsTheReview_ratherThanReviewingBlind() async {
        // Without the replies, a re-run would re-raise issues the author already
        // answered and request changes again — worse than not running.
        struct Boom: Error {}
        var ran = false
        let store = makeStore(
            loadFollowUp: { _ in throw Boom() },
            run: { _, _, _, _ in ran = true; return .failed("unused") },
            resolveApprover: { _ in self.resolution(default: self.acct()) })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertFalse(ran)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertTrue(m.contains("對話"))
    }

    func test_reviewBody_carriesTheMarker_andTracksPreviousIssues() {
        var review = ClaudeReview(verdict: .approve, summary: "- 都處理了", issues: [], raw: "")
        review.previous = [
            .init(issue: "null deref", status: .fixed, note: "c3 加了 guard"),
            .init(issue: "race", status: .justified, note: "只在 main actor 執行"),
            .init(issue: "leak", status: .open, note: "回覆沒有涵蓋背景路徑"),
        ]
        let body = AIReviewStore.reviewBody(from: review)
        XCTAssertTrue(AIReviewMarker.isAIReview(body), "the next run must be able to find this review")
        XCTAssertTrue(body.hasPrefix(AIReviewMarker.tag), "the marker is invisible on GitHub")
        XCTAssertTrue(body.contains("### 前次問題追蹤"))
        XCTAssertTrue(body.contains("✅ 已修正 — null deref — c3 加了 guard"))
        XCTAssertTrue(body.contains("💬 理由採納 — race — 只在 main actor 執行"))
        XCTAssertTrue(body.contains("❌ 仍未解決 — leak — 回覆沒有涵蓋背景路徑"))
    }

    func test_reviewBody_withoutPreviousIssues_omitsTheTrackingSection() {
        let body = AIReviewStore.reviewBody(from: ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: ""))
        XCTAssertFalse(body.contains("### 前次問題追蹤"))
    }

    func test_reviewFailed_setsFailed() async {
        let store = makeStore(run: { _, _, _, _ in .failed("claude missing") }, resolveApprover: { _ in self.resolution(default: self.acct()) })
        let row = prRow(); store.start(row: row); await settle(store, row)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(m, "claude missing")
    }

    func test_phasesAreIndependentPerPR() async {
        let store = makeStore(
            run: { _, _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            resolveApprover: { _ in self.resolution(default: self.acct()) })
        let a = prRow(number: 1), b = prRow(number: 2)
        store.start(row: a); await settle(store, a)
        guard case .done = store.phase(for: a) else { return XCTFail() }
        guard case .idle = store.phase(for: b) else { return XCTFail("B untouched → idle") }
    }

    /// Regression: a PR's review state must be keyed by a stable identifier
    /// (repo id + number), NOT by `PullRequest.id`, which `GitHubAPIClient` mints
    /// fresh on every fetch. Reproduces Back → list refresh (PR re-fetched with a
    /// new id) → re-open: the running/finished review must still be found.
    func test_phaseKeyedByRepoAndNumber_notByVolatilePRId() async {
        let fixedRepo = repo()   // one repo instance → stable repo.id
        func rowFreshPRId() -> PRRow { prRow(number: 7, repo: fixedRepo) }
        let store = makeStore(
            run: { _, _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            resolveApprover: { _ in self.resolution(default: self.acct()) })
        let first = rowFreshPRId()
        store.start(row: first)
        await settle(store, first)
        let second = rowFreshPRId()                        // fresh volatile PullRequest.id
        XCTAssertNotEqual(first.pr.id, second.pr.id, "precondition: volatile id differs")
        guard case .done = store.phase(for: second) else {
            return XCTFail("phase must resolve via repo.id+number, not the volatile PullRequest.id")
        }
    }

    func test_selectApprover_usesPickedAccount_notDefault() async {
        let a = account("alice"), b = account("bob")
        var actedAs: String?
        let store = makeStore(
            run: { _, _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            resolveApprover: { _ in self.resolution(default: a, eligible: [a, b]) },
            approve: { _, acc, _ in actedAs = acc.login; return nil })
        let row = prRow()
        store.selectApprover(b.id, for: row)
        store.start(row: row); await settle(store, row)
        XCTAssertEqual(actedAs, "bob", "review acts as the user's pick, not the default")
        guard case .done(_, let actedAsName) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(actedAsName, "bob")
    }

    func test_selectedApprover_fallsBackToDefault_whenPickNoLongerEligible() async {
        let a = account("alice"), b = account("bob")
        var actedAs: String?
        let store = makeStore(
            run: { _, _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            resolveApprover: { _ in self.resolution(default: a, eligible: [a]) },  // b dropped out
            approve: { _, acc, _ in actedAs = acc.login; return nil })
        let row = prRow()
        store.selectApprover(b.id, for: row)   // a pick that's no longer eligible
        store.start(row: row); await settle(store, row)
        XCTAssertEqual(actedAs, "alice", "a stale pick falls back to the resolved default")
    }

    func test_selectedApprover_isPerRepoAndReadsBack() {
        let b = account("bob")
        let store = makeStore(run: { _, _, _, _ in .failed("unused") })
        let repoA = repo()
        let rowA1 = prRow(number: 1, repo: repoA)
        let rowA2 = prRow(number: 2, repo: repoA)   // same repo, different PR
        let rowB = prRow(number: 1)                 // different repo
        store.selectApprover(b.id, for: rowA1)
        XCTAssertEqual(store.selectedApproverId(for: rowA1), b.id)
        XCTAssertEqual(store.selectedApproverId(for: rowA2), b.id, "pick is per-repo, shared across that repo's PRs")
        XCTAssertNil(store.selectedApproverId(for: rowB), "another repo is unaffected")
    }

    func test_effectiveApprover_prefersEligiblePickOverDefault() {
        let a = account("alice"), b = account("bob")
        let res = resolution(default: a, eligible: [a, b])
        XCTAssertEqual(AIReviewStore.effectiveApprover(resolution: res, selectedId: b.id)?.login, "bob")
        XCTAssertEqual(AIReviewStore.effectiveApprover(resolution: res, selectedId: nil)?.login, "alice")
        XCTAssertEqual(AIReviewStore.effectiveApprover(resolution: res, selectedId: UUID())?.login, "alice", "unknown pick → default")
        XCTAssertNil(AIReviewStore.effectiveApprover(resolution: resolution(default: nil), selectedId: b.id))
    }

    func test_reviewBody_approve_hasApprovedHeaderFooter_noIssueSection() {
        let body = AIReviewStore.reviewBody(from: ClaudeReview(verdict: .approve, summary: "- 全部 OK", issues: [], raw: ""))
        XCTAssertTrue(body.contains("## ✅ AI Review · Approved"))
        XCTAssertTrue(body.contains("- 全部 OK"))
        XCTAssertTrue(body.contains("Reviewed by Claude Code"))
        XCTAssertFalse(body.contains("### 需處理的問題"), "approve has no issues section")
    }

    func test_reviewBody_issuesFound_hasWarningHeaderAndIssueList() {
        let body = AIReviewStore.reviewBody(from: ClaudeReview(
            verdict: .issuesFound, summary: "- 有風險", issues: ["null deref", "race"], raw: ""))
        XCTAssertTrue(body.contains("## ⚠️ AI Review · 發現需處理的問題"))
        XCTAssertTrue(body.contains("### 需處理的問題"))
        XCTAssertTrue(body.contains("- null deref"))
        XCTAssertTrue(body.contains("- race"))
        XCTAssertTrue(body.contains("Reviewed by Claude Code"))
    }

    func test_reviewBody_issuesFound_noIssues_omitsIssueSection() {
        let body = AIReviewStore.reviewBody(from: ClaudeReview(
            verdict: .issuesFound, summary: "flagged", issues: [], raw: ""))
        XCTAssertTrue(body.contains("flagged"))
        XCTAssertFalse(body.contains("### 需處理的問題"))
    }
}
