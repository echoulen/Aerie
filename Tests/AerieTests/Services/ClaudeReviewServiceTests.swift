import XCTest
@testable import Aerie

/// Stream stub: `which` succeeds; `claude` replays scripted stdout lines via onLine,
/// then returns `exitCode`. If `hang` is true, it never emits and never returns
/// until cancelled (to exercise idle-timeout).
private final class StreamStubRunner: SubprocessRunner, @unchecked Sendable {
    var whichCode: Int32 = 0
    var whichOut = "/opt/homebrew/bin/claude"
    var lines: [String] = []
    var exitCode: Int32 = 0
    var hang = false
    private(set) var ranClaude = false
    private(set) var lastCwd: URL?
    private(set) var lastArgs: [String] = []

    func run(_ command: String, _ args: [String], cwd: URL?) async throws -> (String, String, Int32) {
        if command == "which" { return (whichOut, "", whichCode) }
        return ("", "", 0)
    }
    func stream(_ command: String, _ args: [String], cwd: URL?,
                onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        guard command == "claude" else { return 0 }
        ranClaude = true; lastCwd = cwd; lastArgs = args
        if hang {
            try await Task.sleep(nanoseconds: 60 * 1_000_000_000)  // cancelled long before
            return -1
        }
        for l in lines { onLine(l) }
        return exitCode
    }
}

final class ClaudeReviewServiceTests: XCTestCase {
    private func svc(_ runner: SubprocessRunner, idle: TimeInterval = 5, total: TimeInterval = 30) -> LiveClaudeReviewService {
        LiveClaudeReviewService(runner: runner, idleTimeout: idle, totalTimeout: total)
    }
    private func review(_ s: LiveClaudeReviewService, model: ClaudeModel = .sonnet5,
                        onLine: @escaping @Sendable (String) -> Void = { _ in },
                        localPath: URL = URL(fileURLWithPath: "/tmp")) async -> ClaudeReviewOutcome {
        await s.review(owner: "echoulen", repo: "aerie", number: 42, title: "T",
                       author: "octocat", sourceBranch: "feat/x", diff: "DIFF", followUp: nil, guidance: .default,
                       localPath: localPath, model: model, onLine: onLine)
    }

    func test_streamsProgress_andParsesVerdict() async {
        let r = StreamStubRunner()
        r.lines = [
            #"{"type":"system","subtype":"hook_started","hook_name":"SessionStart:startup"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"A.swift"}}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"looks fine"}]}}"#,
            #"{"type":"result","subtype":"success","result":"{\"verdict\":\"approve\",\"summary\":\"LGTM\",\"issues\":[]}"}"#,
        ]
        let box = LineCollector()
        let outcome = await review(svc(r), onLine: { box.add($0) })
        guard case .success(let rev) = outcome else { return XCTFail("expected success") }
        XCTAssertEqual(rev.verdict, .approve)
        // The command echo and startup lines show before claude's own output;
        // the result JSON is never shown.
        XCTAssertEqual(box.lines, [
            "$ claude -p <review prompt> --model claude-sonnet-5",
            "› running hook SessionStart:startup",
            "Read A.swift",
            "looks fine",
        ])
    }

    /// Review is read-only: `--tools` must restrict the session to Read/Grep/Glob
    /// (`--allowedTools` alone leaves Bash and the rest available), and partial
    /// messages are streamed so progress appears while claude thinks.
    func test_restrictsToolsToReadOnly_andStreamsPartialMessages() async {
        let r = StreamStubRunner()
        r.lines = [#"{"type":"result","subtype":"success","result":"{\"verdict\":\"approve\",\"summary\":\"s\",\"issues\":[]}"}"#]
        _ = await review(svc(r))
        guard let i = r.lastArgs.firstIndex(of: "--tools") else { return XCTFail("missing --tools") }
        XCTAssertEqual(r.lastArgs[i + 1], "Read,Grep,Glob")
        XCTAssertTrue(r.lastArgs.contains("--include-partial-messages"))
    }

    func test_claudeMissing_fails_noStream() async {
        let r = StreamStubRunner(); r.whichCode = 1
        let outcome = await review(svc(r))
        guard case .failed(let m) = outcome else { return XCTFail() }
        XCTAssertTrue(m.lowercased().contains("claude"))
        XCTAssertFalse(r.ranClaude)
    }

    func test_nonZeroExit_fails() async {
        let r = StreamStubRunner(); r.lines = []; r.exitCode = 1
        guard case .failed = await review(svc(r)) else { return XCTFail() }
    }

    func test_noVerdictInResult_fails() async {
        let r = StreamStubRunner()
        r.lines = [#"{"type":"result","subtype":"success","result":"I could not decide"}"#]
        guard case .failed = await review(svc(r)) else { return XCTFail() }
    }

    func test_idleTimeout_killsAndFails() async {
        let r = StreamStubRunner(); r.hang = true
        let outcome = await review(svc(r, idle: 0.1, total: 5))
        guard case .failed(let m) = outcome else { return XCTFail("expected timeout failure") }
        XCTAssertTrue(m.contains("進度") || m.contains("逾時"))
    }

    func test_cancellingTheCaller_endsTheReviewPromptly() async {
        // AI Review's Stop cancels the store's task; the running CLI must be
        // cancelled with it, not left until the idle timeout.
        let runner = StreamStubRunner(); runner.hang = true
        let service = svc(runner, idle: 20, total: 60)
        let started = Date()
        let task = Task { await self.review(service) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(runner.ranClaude)
        task.cancel()
        let outcome = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "cancellation propagates to the CLI run")
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
    }

    func test_existingLocalPath_usedAsCwd() async {
        let r = StreamStubRunner()
        r.lines = [#"{"type":"result","result":"{\"verdict\":\"approve\",\"summary\":\"x\",\"issues\":[]}"}"#]
        _ = await review(svc(r), localPath: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(r.lastCwd, URL(fileURLWithPath: "/tmp"))
    }

    func test_modelFlag_passedToArgs() async {
        let r = StreamStubRunner()
        r.lines = [#"{"type":"result","result":"{\"verdict\":\"approve\",\"summary\":\"x\",\"issues\":[]}"}"#]
        _ = await review(svc(r), model: .opus5)
        guard let i = r.lastArgs.firstIndex(of: "--model") else { return XCTFail("no --model flag") }
        XCTAssertEqual(r.lastArgs[i + 1], "claude-opus-5")
    }
}
