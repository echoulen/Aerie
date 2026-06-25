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
        run: @escaping (PRRow, String, @escaping @Sendable (String) -> Void) async -> ClaudeReviewOutcome,
        resolveApprover: @escaping (PRRow) async -> ApproverResolution = { _ in ApproverResolution(eligible: [], defaultApprover: nil) },
        approve: @escaping (PRRow, GitHubAccount, String) async -> String? = { _, _, _ in nil },
        comment: @escaping (PRRow, GitHubAccount, String) async -> String? = { _, _, _ in nil }
    ) -> AIReviewStore {
        AIReviewStore(loadFiles: files, runReview: run, resolveApprover: resolveApprover,
                      approve: approve, comment: comment)
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
        let store = makeStore(run: { _, _, _ in ran = true; return .failed("x") }, resolveApprover: { _ in self.resolution(default: nil) })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertFalse(ran)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertTrue(m.contains("approver"))
    }

    func test_approveVerdict_callsApprove_doneWithActedAs() async {
        var approveBody: String?
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "LGTM", issues: [], raw: "")) },
            resolveApprover: { _ in self.resolution(default: self.acct("reviewer")) },
            approve: { _, a, b in approveBody = b; XCTAssertEqual(a.login, "reviewer"); return nil })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertTrue(approveBody?.contains("LGTM") == true, "approve body carries Claude's summary")
        XCTAssertTrue(approveBody?.contains("## ✅ AI Review · Approved") == true, "wrapped in the formatted markdown body, not a bare summary")
        guard case .done(let r, let actedAs) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(r.verdict, .approve); XCTAssertEqual(actedAs, "reviewer")
    }

    func test_issuesFound_callsComment_notApprove() async {
        var approveCalled = false, commentBody: String?
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .issuesFound, summary: "bug", issues: ["x"], raw: "")) },
            resolveApprover: { _ in self.resolution(default: self.acct()) },
            approve: { _, _, _ in approveCalled = true; return nil },
            comment: { _, _, b in commentBody = b; return nil })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertFalse(approveCalled)
        XCTAssertTrue(commentBody?.contains("x") == true)
        guard case .done = store.phase(for: row) else { return XCTFail() }
    }

    func test_reviewFailed_setsFailed() async {
        let store = makeStore(run: { _, _, _ in .failed("claude missing") }, resolveApprover: { _ in self.resolution(default: self.acct()) })
        let row = prRow(); store.start(row: row); await settle(store, row)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(m, "claude missing")
    }

    func test_phasesAreIndependentPerPR() async {
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
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
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
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
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
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
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            resolveApprover: { _ in self.resolution(default: a, eligible: [a]) },  // b dropped out
            approve: { _, acc, _ in actedAs = acc.login; return nil })
        let row = prRow()
        store.selectApprover(b.id, for: row)   // a pick that's no longer eligible
        store.start(row: row); await settle(store, row)
        XCTAssertEqual(actedAs, "alice", "a stale pick falls back to the resolved default")
    }

    func test_selectedApprover_isPerRepoAndReadsBack() {
        let b = account("bob")
        let store = makeStore(run: { _, _, _ in .failed("unused") })
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
