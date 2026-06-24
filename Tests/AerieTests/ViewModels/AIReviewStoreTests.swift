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
    private func prRow(number: Int = 1) -> PRRow {
        let pr = PullRequest(id: UUID(), repoId: UUID(), number: number, title: "T",
            authorLogin: "octocat", sourceBranch: "feat/x", isMine: false, state: .open,
            ciState: .success, reviewState: .reviewRequired, labels: [],
            htmlUrl: URL(string: "https://e.com")!, updatedAt: Date(timeIntervalSince1970: 1))
        return PRRow(pr: pr, repo: repo(), localState: nil)
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
    private func settle(_ store: AIReviewStore, _ id: UUID) async {
        for _ in 0..<200 {
            if case .running = store.phase(for: id) { await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000) }
            else if case .idle = store.phase(for: id) { await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000) }
            else { return }
        }
    }

    func test_noApprover_failsWithoutRunning() async {
        var ran = false
        let store = makeStore(run: { _, _, _ in ran = true; return .failed("x") }, approver: { _ in nil })
        let row = prRow(); store.start(row: row); await settle(store, row.pr.id)
        XCTAssertFalse(ran)
        guard case .failed(let m) = store.phase(for: row.pr.id) else { return XCTFail() }
        XCTAssertTrue(m.contains("approver"))
    }

    func test_approveVerdict_callsApprove_doneWithActedAs() async {
        var approveBody: String?
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "LGTM", issues: [], raw: "")) },
            approver: { _ in self.acct("reviewer") },
            approve: { _, a, b in approveBody = b; XCTAssertEqual(a.login, "reviewer"); return nil })
        let row = prRow(); store.start(row: row); await settle(store, row.pr.id)
        XCTAssertEqual(approveBody, "LGTM")
        guard case .done(let r, let actedAs) = store.phase(for: row.pr.id) else { return XCTFail() }
        XCTAssertEqual(r.verdict, .approve); XCTAssertEqual(actedAs, "reviewer")
    }

    func test_issuesFound_callsComment_notApprove() async {
        var approveCalled = false, commentBody: String?
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .issuesFound, summary: "bug", issues: ["x"], raw: "")) },
            approver: { _ in self.acct() },
            approve: { _, _, _ in approveCalled = true; return nil },
            comment: { _, _, b in commentBody = b; return nil })
        let row = prRow(); store.start(row: row); await settle(store, row.pr.id)
        XCTAssertFalse(approveCalled)
        XCTAssertTrue(commentBody?.contains("x") == true)
        guard case .done = store.phase(for: row.pr.id) else { return XCTFail() }
    }

    func test_reviewFailed_setsFailed() async {
        let store = makeStore(run: { _, _, _ in .failed("claude missing") }, approver: { _ in self.acct() })
        let row = prRow(); store.start(row: row); await settle(store, row.pr.id)
        guard case .failed(let m) = store.phase(for: row.pr.id) else { return XCTFail() }
        XCTAssertEqual(m, "claude missing")
    }

    func test_phasesAreIndependentPerPR() async {
        let store = makeStore(
            run: { _, _, _ in .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            approver: { _ in self.acct() })
        let a = prRow(number: 1), b = prRow(number: 2)
        store.start(row: a); await settle(store, a.pr.id)
        guard case .done = store.phase(for: a.pr.id) else { return XCTFail() }
        guard case .idle = store.phase(for: b.pr.id) else { return XCTFail("B untouched → idle") }
    }

    func test_commentBody_noIssues_omitsBulletList() {
        let body = AIReviewStore.commentBody(from: ClaudeReview(verdict: .issuesFound, summary: "flagged", issues: [], raw: ""))
        XCTAssertTrue(body.contains("flagged"))
        XCTAssertFalse(body.contains("- "))
    }
}
