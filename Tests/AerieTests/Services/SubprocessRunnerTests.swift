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
