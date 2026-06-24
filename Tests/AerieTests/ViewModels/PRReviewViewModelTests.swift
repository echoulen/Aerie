import XCTest
@testable import Aerie

@MainActor
final class PRReviewViewModelTests: XCTestCase {
    private let boundId = UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!

    private func makeRepo() -> Repository {
        Repository(
            id: UUID(), name: "aerie",
            localPath: URL(fileURLWithPath: "/tmp/aerie"),
            githubOwner: "echoulen", githubRepo: "aerie",
            defaultBranch: "main", primaryAccountId: boundId,
            sortOrder: 0, hidden: false)
    }

    private func makePR(author: String) -> PullRequest {
        PullRequest(
            id: UUID(), repoId: UUID(), number: 42, title: "Add review screen",
            authorLogin: author, sourceBranch: "feat/x", isMine: author == "echoulen",
            state: .open, ciState: .success, reviewState: .reviewRequired,
            labels: [], htmlUrl: URL(string: "https://example.com")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func row(author: String) -> PRRow {
        PRRow(pr: makePR(author: author), repo: makeRepo(), localState: nil)
    }

    private let file = PRFileChange(
        filename: "A.swift", status: .modified, additions: 3, deletions: 1, patch: "@@ -1 +1 @@\n-a\n+b")

    func test_load_withFiles_becomesReady() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { [GitHubAccount(id: self.boundId, login: "reviewer", host: "github.com")] })
        await vm.load()
        XCTAssertEqual(vm.state, .ready([file]))
    }

    func test_load_noFiles_becomesEmpty() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [] },
            accountsProvider: { [] })
        await vm.load()
        XCTAssertEqual(vm.state, .empty)
    }

    func test_load_throwing_becomesError() async {
        struct Boom: LocalizedError { var errorDescription: String? { "kaboom" } }
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in throw Boom() },
            accountsProvider: { [] })
        await vm.load()
        XCTAssertEqual(vm.state, .error("kaboom"))
    }

    func test_load_resolvesBoundAccountAsApprover() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { [GitHubAccount(id: self.boundId, login: "reviewer", host: "github.com")] })
        await vm.load()
        XCTAssertEqual(vm.resolution.defaultApprover?.id, boundId)
        XCTAssertTrue(vm.resolution.canApprove)
    }

    func test_load_ownPR_picksOtherAccountAsApprover() async {
        let other = GitHubAccount(id: UUID(), login: "teammate", host: "github.com")
        let vm = PRReviewViewModel(
            row: row(author: "echoulen"),
            loadFiles: { _ in [self.file] },
            accountsProvider: {
                [GitHubAccount(id: self.boundId, login: "echoulen", host: "github.com"), other]
            })
        await vm.load()
        XCTAssertEqual(vm.resolution.defaultApprover?.id, other.id)
    }

    // MARK: - AI Review Tests

    private func reviewer() -> [GitHubAccount] {
        [GitHubAccount(id: boundId, login: "reviewer", host: "github.com")]
    }

    func test_runAIReview_noEligibleApprover_failsWithoutRunning() async {
        var reviewRan = false
        let vm = PRReviewViewModel(
            row: row(author: "reviewer"),               // only account == author → no approver
            loadFiles: { _ in [self.file] },
            accountsProvider: { self.reviewer() },
            runReview: { _, _ in reviewRan = true; return .success(
                ClaudeReview(verdict: .approve, summary: "x", issues: [], raw: "")) },
            submitApprove: { _, _ in nil },
            submitComment: { _, _ in nil })
        await vm.load()
        await vm.runAIReview()
        XCTAssertFalse(reviewRan)
        guard case .failed(let msg) = vm.aiReview else { return XCTFail("expected .failed") }
        XCTAssertTrue(msg.contains("approver"))
    }

    func test_runAIReview_approveVerdict_callsApprove_andDone() async {
        var approveBody: String?
        var commentCalled = false
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { self.reviewer() },
            runReview: { _, _ in .success(
                ClaudeReview(verdict: .approve, summary: "LGTM", issues: [], raw: "")) },
            submitApprove: { _, body in approveBody = body; return nil },
            submitComment: { _, _ in commentCalled = true; return nil })
        await vm.load()
        await vm.runAIReview()
        XCTAssertEqual(approveBody, "LGTM")
        XCTAssertFalse(commentCalled)
        guard case .done(let r) = vm.aiReview else { return XCTFail("expected .done") }
        XCTAssertEqual(r.verdict, .approve)
    }

    func test_runAIReview_issuesFound_callsComment_notApprove() async {
        var approveCalled = false
        var commentBody: String?
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { self.reviewer() },
            runReview: { _, _ in .success(
                ClaudeReview(verdict: .issuesFound, summary: "bug", issues: ["null deref"], raw: "")) },
            submitApprove: { _, _ in approveCalled = true; return nil },
            submitComment: { _, body in commentBody = body; return nil })
        await vm.load()
        await vm.runAIReview()
        XCTAssertFalse(approveCalled)
        XCTAssertNotNil(commentBody)
        XCTAssertTrue(commentBody!.contains("null deref"))
        guard case .done = vm.aiReview else { return XCTFail("expected .done") }
    }

    func test_runAIReview_reviewFailed_setsFailed() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { self.reviewer() },
            runReview: { _, _ in .failed("claude missing") },
            submitApprove: { _, _ in nil },
            submitComment: { _, _ in nil })
        await vm.load()
        await vm.runAIReview()
        guard case .failed(let msg) = vm.aiReview else { return XCTFail("expected .failed") }
        XCTAssertEqual(msg, "claude missing")
    }

    func test_runAIReview_approveSubmitError_setsFailed() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { self.reviewer() },
            runReview: { _, _ in .success(
                ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            submitApprove: { _, _ in "403 forbidden" },
            submitComment: { _, _ in nil })
        await vm.load()
        await vm.runAIReview()
        guard case .failed(let msg) = vm.aiReview else { return XCTFail("expected .failed") }
        XCTAssertTrue(msg.contains("403"))
    }

    func test_runAIReview_commentSubmitError_setsFailed() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { self.reviewer() },
            runReview: { _, _ in .success(
                ClaudeReview(verdict: .issuesFound, summary: "bug", issues: ["x"], raw: "")) },
            submitApprove: { _, _ in nil },
            submitComment: { _, _ in "422 unprocessable" })
        await vm.load()
        await vm.runAIReview()
        guard case .failed(let msg) = vm.aiReview else { return XCTFail("expected .failed") }
        XCTAssertTrue(msg.contains("422"))
    }

    func test_runAIReview_whileRunning_ignoresReentrantCall() async {
        // Park the first runReview on a continuation so it stays `.running`.
        let gate = Gate()
        var runReviewCalls = 0
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { self.reviewer() },
            runReview: { _, _ in
                runReviewCalls += 1
                await gate.wait()
                return .success(ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: ""))
            },
            submitApprove: { _, _ in nil },
            submitComment: { _, _ in nil })
        await vm.load()

        async let first: Void = vm.runAIReview()     // enters, sets .running, parks in runReview
        // Let `first` advance to the parked await before the second call.
        for _ in 0..<5 { await Task.yield() }
        await vm.runAIReview()                        // hits the guard, returns immediately

        await gate.open()                             // release the first call
        await first

        XCTAssertEqual(runReviewCalls, 1, "re-entrant call must not run a second review")
    }

    func test_runAIReview_emptyDiff_passesEmptyStringToReview() async {
        var capturedDiff: String?
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [] },                 // → state becomes .empty
            accountsProvider: { self.reviewer() },
            runReview: { _, diff in capturedDiff = diff; return .success(
                ClaudeReview(verdict: .approve, summary: "ok", issues: [], raw: "")) },
            submitApprove: { _, _ in nil },
            submitComment: { _, _ in nil })
        await vm.load()
        await vm.runAIReview()
        XCTAssertEqual(capturedDiff, "")
    }

    func test_commentBody_noIssues_omitsBulletList() {
        let body = PRReviewViewModel.commentBody(
            from: ClaudeReview(verdict: .issuesFound, summary: "flagged but no list", issues: [], raw: ""))
        XCTAssertTrue(body.contains("flagged but no list"))
        XCTAssertFalse(body.contains("- "))
    }
}

/// A one-shot async gate: `wait()` suspends until `open()` is called.
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
