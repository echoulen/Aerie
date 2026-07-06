import XCTest
@testable import Aerie

/// Stream stub: `which` succeeds; `claude` replays scripted stdout lines via
/// onLine, then returns `exitCode`. If `hang` is true, it never emits and
/// never returns until cancelled (to exercise the idle watchdog).
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

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ s: String) { lock.lock(); stored.append(s); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}

final class PRCreateServiceTests: XCTestCase {
    private func svc(_ runner: SubprocessRunner, idle: TimeInterval = 5, total: TimeInterval = 30) -> LivePRCreateService {
        LivePRCreateService(runner: runner, idleTimeout: idle, totalTimeout: total)
    }

    /// `localPath` must exist as a directory (the service hard-requires the
    /// checkout); /tmp always does.
    private func create(
        _ s: LivePRCreateService,
        template: String = "publish {{OWNER}}/{{REPO}}",
        localPath: URL = URL(fileURLWithPath: "/tmp"),
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> PRCreateOutcome {
        await s.createPR(
            template: template, owner: "echoulen", repo: "aerie",
            defaultBranch: "main", currentBranch: "main",
            statusSummary: "working tree dirty (2 files)",
            localPath: localPath, onLine: onLine)
    }

    func test_streamsProgress_andParsesCreated() async {
        let r = StreamStubRunner()
        r.lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git push -u origin feat/x"}}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"pushing branch"}]}}"#,
            #"{"type":"result","subtype":"success","result":"{\"outcome\":\"created\",\"pr_number\":7,\"pr_url\":\"https://github.com/echoulen/aerie/pull/7\",\"summary\":\"done\"}"}"#,
        ]
        let box = Collected()
        let outcome = await create(svc(r), onLine: { box.add($0) })
        guard case .created(let n, let url, _) = outcome else { return XCTFail("expected created, got \(outcome)") }
        XCTAssertEqual(n, 7)
        XCTAssertEqual(url.absoluteString, "https://github.com/echoulen/aerie/pull/7")
        XCTAssertEqual(box.lines, ["Using Bash", "pushing branch"])
    }

    func test_promptRendered_andWhitelistArgs() async {
        let r = StreamStubRunner()
        r.lines = [#"{"type":"result","subtype":"success","result":"{\"outcome\":\"nothing_to_do\",\"summary\":\"s\"}"}"#]
        _ = await create(svc(r), template: "T {{OWNER}}/{{REPO}} {{STATUS_SUMMARY}}")
        XCTAssertEqual(r.lastArgs.first, "-p")
        XCTAssertEqual(r.lastArgs[1], "T echoulen/aerie working tree dirty (2 files)")
        guard let i = r.lastArgs.firstIndex(of: "--allowedTools") else { return XCTFail() }
        XCTAssertEqual(r.lastArgs[i + 1], "Read,Grep,Glob,Bash(git:*),Bash(gh:*)")
        XCTAssertEqual(r.lastCwd, URL(fileURLWithPath: "/tmp"))
    }

    func test_claudeMissing_fails_noStream() async {
        let r = StreamStubRunner(); r.whichCode = 1
        guard case .failed(let m) = await create(svc(r)) else { return XCTFail() }
        XCTAssertTrue(m.contains("claude"))
        XCTAssertFalse(r.ranClaude)
    }

    func test_missingLocalPath_fails_noStream() async {
        let r = StreamStubRunner()
        let bogus = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        guard case .failed = await create(svc(r), localPath: bogus) else { return XCTFail() }
        XCTAssertFalse(r.ranClaude)
    }

    func test_nonZeroExit_fails() async {
        let r = StreamStubRunner(); r.exitCode = 1
        guard case .failed = await create(svc(r)) else { return XCTFail() }
    }

    func test_noOutcomeJson_fails() async {
        let r = StreamStubRunner()
        r.lines = [#"{"type":"result","subtype":"success","result":"did stuff, no json"}"#]
        guard case .failed = await create(svc(r)) else { return XCTFail() }
    }

    func test_claudeReportedFailure_surfacesSummary() async {
        let r = StreamStubRunner()
        r.lines = [#"{"type":"result","subtype":"success","result":"{\"outcome\":\"failed\",\"summary\":\"remote rejected\"}"}"#]
        guard case .failed(let m) = await create(svc(r)) else { return XCTFail() }
        XCTAssertEqual(m, "remote rejected")
    }

    func test_idleTimeout_killsAndFails() async {
        let r = StreamStubRunner(); r.hang = true
        guard case .failed(let m) = await create(svc(r, idle: 0.1, total: 30)) else { return XCTFail() }
        XCTAssertTrue(m.contains("沒有新進度"))
    }
}
