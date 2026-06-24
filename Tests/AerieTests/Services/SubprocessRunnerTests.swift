import XCTest
@testable import Aerie

final class SubprocessRunnerTests: XCTestCase {
    func test_runsTrueAndReturnsExitZero() async throws {
        let runner = LiveSubprocessRunner()
        let (_, _, rc) = try await runner.run("true", [])
        XCTAssertEqual(rc, 0)
    }

    // MARK: - PATH augmentation
    //
    // A GUI app launched from Finder/LaunchServices inherits only the minimal
    // launchd PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), which omits Homebrew —
    // so `which gh` failed and Aerie wrongly showed "Install GitHub CLI".

    func test_augmentedPATH_prependsHomebrewAndKeepsExisting() {
        let parts = SubprocessPATH.augmented(base: "/usr/bin:/bin")
            .split(separator: ":").map(String.init)
        XCTAssertEqual(parts.first, "/opt/homebrew/bin", "Homebrew bin must come first")
        XCTAssertTrue(parts.contains("/usr/local/bin"), "Intel/other Homebrew prefix included")
        XCTAssertTrue(parts.contains("/usr/bin"), "existing entries preserved")
        XCTAssertTrue(parts.contains("/bin"))
        XCTAssertEqual(parts.count, Set(parts).count, "no duplicate entries")
    }

    func test_augmentedPATH_dedupesWhenAlreadyPresent() {
        let parts = SubprocessPATH.augmented(base: "/opt/homebrew/bin:/usr/bin")
            .split(separator: ":").map(String.init)
        XCTAssertEqual(parts.filter { $0 == "/opt/homebrew/bin" }.count, 1)
    }

    func test_augmentedPATH_emptyBaseStillHasHomebrewAndSystemDirs() {
        let parts = SubprocessPATH.augmented(base: "")
            .split(separator: ":").map(String.init)
        XCTAssertTrue(parts.contains("/opt/homebrew/bin"))
        XCTAssertTrue(parts.contains("/usr/bin"))
    }

    func test_augmentedPATH_includesLocalBinForNativeClaude() {
        let parts = SubprocessPATH.augmented(base: "/usr/bin")
            .split(separator: ":").map(String.init)
        XCTAssertTrue(parts.contains("\(NSHomeDirectory())/.local/bin"),
                      "~/.local/bin (Claude Code native installer) must be searched")
    }

    func test_augmentedPATH_localBinBeatsSupersetShim() {
        let home = NSHomeDirectory()
        // base puts the superset shim ahead of ~/.local/bin, as the user's shell PATH does.
        let parts = SubprocessPATH.augmented(base: "\(home)/.superset/bin:\(home)/.local/bin:/usr/bin")
            .split(separator: ":").map(String.init)
        guard let localIdx = parts.firstIndex(of: "\(home)/.local/bin"),
              let shimIdx = parts.firstIndex(of: "\(home)/.superset/bin") else {
            return XCTFail("both ~/.local/bin and ~/.superset/bin should be present")
        }
        XCTAssertLessThan(localIdx, shimIdx,
                          "native ~/.local/bin must resolve before the superset wrapper")
    }

    // MARK: - extra-env injection
    //
    // Git operations against a private remote must authenticate as the account
    // bound to that repo, not gh's globally-active account. We achieve that by
    // injecting `GH_TOKEN` into the `git` subprocess environment so the
    // `gh auth git-credential` helper serves that account's token. The merge
    // must not clobber the augmented PATH.

    func test_environment_mergesExtraEntriesOverProcessEnv() {
        let env = SubprocessPATH.environment(extra: ["GH_TOKEN": "tok-123"])
        XCTAssertEqual(env["GH_TOKEN"], "tok-123", "extra entries are injected")
        let pathDirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        XCTAssertTrue(
            pathDirs.contains("/opt/homebrew/bin"),
            "PATH stays augmented when extra env is supplied"
        )
    }

    func test_environment_noExtraDoesNotInventKeys() {
        let env = SubprocessPATH.environment()
        XCTAssertNil(
            env["AERIE_NONEXISTENT_VAR_XYZ"],
            "environment() must not invent keys that weren't asked for"
        )
        XCTAssertFalse((env["PATH"] ?? "").isEmpty, "PATH is always present")
    }

    // MARK: - Pipe-buffer deadlock
    //
    // Reading a child's stdout/stderr only AFTER it exits deadlocks once the
    // child writes more than the OS pipe buffer (~64 KiB): it blocks on write()
    // waiting for the pipe to be drained, but nothing drains it until the process
    // terminates — so it never terminates. The runner must drain both streams
    // concurrently while the process runs.

    func test_run_largeStdoutAndStderr_doesNotDeadlock() async {
        let runner = LiveSubprocessRunner()
        let bytes = 200_000  // well past the ~64 KiB OS pipe buffer

        // Run on an UNSTRUCTURED task we never await: a deadlocked `run()` parks
        // on a continuation that never resumes and a child blocked on write(),
        // and `withCheckedContinuation` is not cancellation-aware — so awaiting
        // it (e.g. via a task group) would hang the whole suite instead of
        // failing. Polling a flag lets the test fail cleanly at the 8 s bound.
        let box = ResultBox()
        let task = Task {
            let r = try? await runner.run(
                "sh",
                ["-c", "yes | head -c \(bytes); yes | head -c \(bytes) 1>&2"]
            )
            box.finish(r)
        }
        for _ in 0..<80 where !box.isDone {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 80 × 100 ms = 8 s
        }
        task.cancel()  // best-effort; a deadlocked continuation won't observe it

        guard let (out, err, rc) = box.value else {
            return XCTFail("run() deadlocked draining >64 KiB of stdout/stderr (no return within 8 s)")
        }
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(out.utf8.count, bytes, "full stdout must be captured")
        XCTAssertEqual(err.utf8.count, bytes, "full stderr must be captured")
    }

    // MARK: - waitUntilExit() wakeup race
    //
    // `run()` awaited the child via `Process.waitUntilExit()` on a
    // `DispatchQueue.global()` worker thread. That wait is unreliable there:
    // `sample` caught a run() parked forever in `_pthread_mutex_firstfit_lock_wait`
    // inside waitUntilExit *after the child had already been reaped*. That froze
    // `GhBootstrapper` — its `await auth.bootstrap()` never returned — so the UI
    // sat on the bare-Backdrop `.none` state: a black screen. The race surfaces
    // under bursts of fast-terminating children, so fire many at once and require
    // every one to return within the bound.

    // MARK: - Working directory

    func test_run_respectsCwd() async throws {
        let runner = LiveSubprocessRunner()
        let tmp = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let (out, _, code) = try await runner.run("pwd", [], cwd: tmp)
        XCTAssertEqual(code, 0)
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "/private/tmp")
    }

    func test_run_withoutCwd_stillWorks() async throws {
        let runner = LiveSubprocessRunner()
        let (out, _, code) = try await runner.run("echo", ["hi"])
        XCTAssertEqual(code, 0)
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "hi")
    }

    func test_run_concurrentShortCommands_allReturn() async {
        let runner = LiveSubprocessRunner()
        let n = 200
        let done = AtomicCounter()
        for _ in 0..<n {
            Task.detached {
                if let r = try? await runner.run("true", []), r.2 == 0 {
                    done.increment()
                }
            }
        }
        // Poll rather than await: a run() parked on a never-resumed continuation
        // would hang the whole suite if awaited directly.
        for _ in 0..<200 where done.value < n {
            try? await Task.sleep(nanoseconds: 100_000_000)  // up to 20 s
        }
        XCTAssertEqual(
            done.value, n,
            "every concurrent subprocess must return; a parked waitUntilExit leaves the count short"
        )
    }

    // MARK: - stream()

    func test_stream_emitsLinesInOrder() async throws {
        let runner = LiveSubprocessRunner()
        let box = LineCollector()
        let code = try await runner.stream("printf", ["a\\nb\\nc\\n"], cwd: nil) { box.add($0) }
        XCTAssertEqual(code, 0)
        XCTAssertEqual(box.lines, ["a", "b", "c"])
    }

    func test_stream_cancellationTerminatesProcess() async throws {
        let runner = LiveSubprocessRunner()
        let task = Task { try await runner.stream("sleep", ["30"], cwd: nil) { _ in } }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let code = try await task.value     // must return promptly, not after 30s
        XCTAssertNotEqual(code, 0)          // terminated by signal → non-zero
    }
}

/// Lock-guarded one-shot holder for a runner result, so the test can poll for
/// completion from one task while another fills it — without awaiting (and thus
/// blocking on) a potentially deadlocked subprocess call.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (String, String, Int32)??

    func finish(_ value: (String, String, Int32)?) {
        lock.lock(); result = .some(value); lock.unlock()
    }
    var isDone: Bool {
        lock.lock(); defer { lock.unlock() }; return result != nil
    }
    var value: (String, String, Int32)? {
        lock.lock(); defer { lock.unlock() }; return result ?? nil
    }
}

/// Thread-safe tally for counting concurrent subprocess completions.
private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// Thread-safe line collector for stream tests.
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    func add(_ s: String) { lock.lock(); _lines.append(s); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
}
