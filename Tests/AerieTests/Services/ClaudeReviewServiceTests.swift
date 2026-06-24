import XCTest
@testable import Aerie

/// Runner whose `claude` call never returns on its own — only cancellation (via
/// the service's timeout) unblocks it. `which` still succeeds.
private final class HangingClaudeRunner: SubprocessRunner, @unchecked Sendable {
    func run(_ command: String, _ args: [String], cwd: URL?) async throws -> (String, String, Int32) {
        if command == "which" { return ("/opt/homebrew/bin/claude", "", 0) }
        try await Task.sleep(nanoseconds: 60 * 1_000_000_000)  // 60s; cancelled long before this
        return ("", "", 0)
    }
}

/// Stub runner that answers by the *first* arg so a long prompt doesn't need to
/// be matched exactly: `which` vs `-p`.
private final class StubClaudeRunner: SubprocessRunner, @unchecked Sendable {
    var whichResult: (String, String, Int32) = ("/opt/homebrew/bin/claude", "", 0)
    var reviewResult: (String, String, Int32) = ("", "", 0)
    private(set) var lastCwd: URL?
    private(set) var ranReview = false

    func run(_ command: String, _ args: [String], cwd: URL?) async throws -> (String, String, Int32) {
        if command == "which" { return whichResult }
        if command == "claude" {
            ranReview = true
            lastCwd = cwd
            return reviewResult
        }
        return ("", "", 0)
    }
}

final class ClaudeReviewServiceTests: XCTestCase {
    private func makeService(_ runner: SubprocessRunner) -> LiveClaudeReviewService {
        LiveClaudeReviewService(runner: runner, timeout: 5)
    }

    private func review(_ svc: LiveClaudeReviewService, localPath: URL) async -> ClaudeReviewOutcome {
        await svc.review(
            owner: "echoulen", repo: "aerie", number: 42,
            title: "T", author: "octocat", sourceBranch: "feat/x",
            diff: "DIFF", localPath: localPath)
    }

    func test_review_whenClaudeMissing_fails_andDoesNotRun() async {
        let runner = StubClaudeRunner()
        runner.whichResult = ("", "", 1)
        let svc = makeService(runner)
        let outcome = await review(svc, localPath: URL(fileURLWithPath: "/tmp"))
        guard case .failed(let msg) = outcome else { return XCTFail("expected .failed") }
        XCTAssertTrue(msg.lowercased().contains("claude"))
        XCTAssertFalse(runner.ranReview)
    }

    func test_review_validApproveJSON_returnsSuccess() async {
        let runner = StubClaudeRunner()
        runner.reviewResult = (#"{"result":"{\"verdict\":\"approve\",\"summary\":\"ok\",\"issues\":[]}"}"#, "", 0)
        let svc = makeService(runner)
        let outcome = await review(svc, localPath: URL(fileURLWithPath: "/tmp"))
        guard case .success(let r) = outcome else { return XCTFail("expected .success") }
        XCTAssertEqual(r.verdict, .approve)
    }

    func test_review_nonZeroExit_fails() async {
        let runner = StubClaudeRunner()
        runner.reviewResult = ("", "boom", 1)
        let svc = makeService(runner)
        let outcome = await review(svc, localPath: URL(fileURLWithPath: "/tmp"))
        guard case .failed = outcome else { return XCTFail("expected .failed") }
    }

    func test_review_unparseableOutput_fails() async {
        let runner = StubClaudeRunner()
        runner.reviewResult = ("not json at all", "", 0)
        let svc = makeService(runner)
        let outcome = await review(svc, localPath: URL(fileURLWithPath: "/tmp"))
        guard case .failed = outcome else { return XCTFail("expected .failed") }
    }

    func test_review_existingLocalPath_usedAsCwd() async {
        let runner = StubClaudeRunner()
        runner.reviewResult = (#"{"verdict":"approve","summary":"ok","issues":[]}"#, "", 0)
        let svc = makeService(runner)
        _ = await review(svc, localPath: URL(fileURLWithPath: "/tmp"))  // /tmp exists
        XCTAssertEqual(runner.lastCwd, URL(fileURLWithPath: "/tmp"))
    }

    func test_review_missingLocalPath_runsWithoutCwd() async {
        let runner = StubClaudeRunner()
        runner.reviewResult = (#"{"verdict":"approve","summary":"ok","issues":[]}"#, "", 0)
        let svc = makeService(runner)
        _ = await review(svc, localPath: URL(fileURLWithPath: "/no/such/dir/\(UUID().uuidString)"))
        XCTAssertNil(runner.lastCwd)
    }

    func test_review_timesOut_whenRunnerHangs() async {
        let svc = LiveClaudeReviewService(runner: HangingClaudeRunner(), timeout: 0.05)
        let outcome = await svc.review(
            owner: "echoulen", repo: "aerie", number: 42,
            title: "T", author: "octocat", sourceBranch: "feat/x",
            diff: "DIFF", localPath: URL(fileURLWithPath: "/tmp"))
        guard case .failed(let msg) = outcome else { return XCTFail("expected .failed on timeout") }
        XCTAssertTrue(msg.contains("逾時"), "expected a timeout message, got: \(msg)")
    }
}
