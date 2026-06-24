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
        approver: @escaping (PRRow) async -> GitHubAccount? = { _ in nil },
        approve: @escaping (PRRow, GitHubAccount, String) async -> String? = { _, _, _ in nil },
        comment: @escaping (PRRow, GitHubAccount, String) async -> String? = { _, _, _ in nil }
    ) -> AIReviewStore {
        AIReviewStore(loadFiles: files, runReview: run, resolveApprover: approver,
                      approve: approve, comment: comment)
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
        let store = makeStore(run: { _, _, _ in ran = true; return .failed("x") }, approver: { _ in nil })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertFalse(ran)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertTrue(m.contains("approver"))
    }

    func test_approveVerdict_callsApprove_doneWithActedAs() async {
        var approveBody: String?
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "LGTM", issues: [], raw: "")) },
            approver: { _ in self.acct("reviewer") },
            approve: { _, a, b in approveBody = b; XCTAssertEqual(a.login, "reviewer"); return nil })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertEqual(approveBody, "LGTM")
        guard case .done(let r, let actedAs) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(r.verdict, .approve); XCTAssertEqual(actedAs, "reviewer")
    }

    func test_issuesFound_callsComment_notApprove() async {
        var approveCalled = false, commentBody: String?
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .issuesFound, summary: "bug", issues: ["x"], raw: "")) },
            approver: { _ in self.acct() },
            approve: { _, _, _ in approveCalled = true; return nil },
            comment: { _, _, b in commentBody = b; return nil })
        let row = prRow(); store.start(row: row); await settle(store, row)
        XCTAssertFalse(approveCalled)
        XCTAssertTrue(commentBody?.contains("x") == true)
        guard case .done = store.phase(for: row) else { return XCTFail() }
    }

    func test_reviewFailed_setsFailed() async {
        let store = makeStore(run: { _, _, _ in .failed("claude missing") }, approver: { _ in self.acct() })
        let row = prRow(); store.start(row: row); await settle(store, row)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(m, "claude missing")
    }

    func test_phasesAreIndependentPerPR() async {
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            approver: { _ in self.acct() })
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
            approver: { _ in self.acct() })
        let first = rowFreshPRId()
        store.start(row: first)
        await settle(store, first)
        let second = rowFreshPRId()                        // fresh volatile PullRequest.id
        XCTAssertNotEqual(first.pr.id, second.pr.id, "precondition: volatile id differs")
        guard case .done = store.phase(for: second) else {
            return XCTFail("phase must resolve via repo.id+number, not the volatile PullRequest.id")
        }
    }

    func test_commentBody_noIssues_omitsBulletList() {
        let body = AIReviewStore.commentBody(from: ClaudeReview(verdict: .issuesFound, summary: "flagged", issues: [], raw: ""))
        XCTAssertTrue(body.contains("flagged"))
        XCTAssertFalse(body.contains("- "))
    }
}
