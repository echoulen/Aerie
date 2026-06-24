import Foundation

protocol SubprocessRunner: Sendable {
    /// Returns (stdout, stderr, exitCode). Throws on launch failure only.
    /// `cwd` sets the child's working directory (nil = inherit the parent's).
    func run(_ command: String, _ args: [String], cwd: URL?) async throws -> (String, String, Int32)
}

extension SubprocessRunner {
    /// Back-compat convenience: run with the inherited working directory.
    func run(_ command: String, _ args: [String]) async throws -> (String, String, Int32) {
        try await run(command, args, cwd: nil)
    }
}

/// Builds the `PATH` used for subprocesses (we shell out via `/usr/bin/env`,
/// which resolves the command against `PATH`).
///
/// A GUI app launched from Finder / LaunchServices inherits only the minimal
/// launchd `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`) — it does NOT source the
/// user's shell profile, so Homebrew's `/opt/homebrew/bin` (Apple Silicon) or
/// `/usr/local/bin` (Intel) is absent. `gh` lives there, so `which gh` failed
/// and Aerie wrongly showed "Install GitHub CLI" even when `gh` was installed.
/// Prepending the common CLI install dirs makes tools resolve regardless of how
/// the app was launched (Finder vs Terminal).
enum SubprocessPATH {
    private static let toolDirs = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
    private static let systemDirs = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    static func augmented(base: String) -> String {
        let baseDirs = base.split(separator: ":").map(String.init)
        var seen = Set<String>()
        var ordered: [String] = []
        for dir in toolDirs + baseDirs + systemDirs where !dir.isEmpty && seen.insert(dir).inserted {
            ordered.append(dir)
        }
        return ordered.joined(separator: ":")
    }

    /// The current process environment with `PATH` augmented as above, plus any
    /// `extra` entries merged in (overriding inherited values).
    ///
    /// `extra` exists so git operations can inject `GH_TOKEN`: the repo's
    /// credential helper is `gh auth git-credential`, which serves gh's
    /// *globally-active* account by default. When fetching a private remote
    /// that only a *different* account can see, that yields a misleading
    /// "Repository not found". Setting `GH_TOKEN` to the repo's bound account's
    /// token makes the helper authenticate as that account instead.
    static func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmented(base: env["PATH"] ?? "")
        for (key, value) in extra { env[key] = value }
        return env
    }
}

struct LiveSubprocessRunner: SubprocessRunner {
    func run(_ command: String, _ args: [String], cwd: URL?) async throws -> (String, String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [command] + args
        p.environment = SubprocessPATH.environment()
        if let cwd { p.currentDirectoryURL = cwd }
        let outPipe = Pipe(); p.standardOutput = outPipe
        let errPipe = Pipe(); p.standardError  = errPipe

        let io = IOResult()
        // Three things must finish before we return: stdout drained to EOF,
        // stderr drained to EOF, and the child terminated.
        let group = DispatchGroup()
        group.enter()  // stdout drained
        group.enter()  // stderr drained
        group.enter()  // process terminated

        return try await withCheckedThrowingContinuation { cont in
            // What tells us the child exited is `terminationHandler`, NOT
            // `waitUntilExit()`. The old code called `p.waitUntilExit()` on a
            // `DispatchQueue.global()` worker thread; that wait is unreliable
            // there — under a burst of concurrent subprocesses it parked forever
            // in `_pthread_mutex_firstfit_lock_wait` even after the child had been
            // reaped, so `run()` never returned. That froze `GhBootstrapper`
            // (its `await auth.bootstrap()` never came back) and left the whole
            // app on a bare-Backdrop black screen. Foundation invokes
            // `terminationHandler` from its own process-management queue, which
            // delivers reliably. Registered *before* `run()` so a child that
            // exits instantly can't fire it before we're listening.
            p.terminationHandler = { _ in group.leave() }
            do {
                try p.run()
            } catch {
                // Launch failed: the handler will never fire, so resume here.
                cont.resume(throwing: error)
                return
            }
            // Drain each pipe on its own short-lived task *while the process
            // runs*, for two reasons:
            //   1. A child writing past the ~64 KiB OS pipe buffer blocks on
            //      `write()` (and never exits) unless someone drains the stream.
            //   2. Each drain runs independently and never blocks waiting on the
            //      other, so firing many run()s at once can't exhaust the global
            //      pool's threads. (Routing both drains through a blocking
            //      `SubprocessIO.drainConcurrently` here starved the pool and
            //      hung under load.)
            DispatchQueue.global().async {
                io.store(out: outPipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
            DispatchQueue.global().async {
                io.store(err: errPipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
            group.notify(queue: .global()) {
                cont.resume(returning: (
                    String(data: io.out, encoding: .utf8) ?? "",
                    String(data: io.err, encoding: .utf8) ?? "",
                    p.terminationStatus
                ))
            }
        }
    }
}

/// Lock-guarded holder for a subprocess's drained stdout/stderr, so the two
/// independent drain tasks can publish their results for the
/// `terminationHandler`-gated resume to read.
private final class IOResult: @unchecked Sendable {
    private let lock = NSLock()
    private var _out = Data()
    private var _err = Data()
    func store(out: Data) { lock.lock(); _out = out; lock.unlock() }
    func store(err: Data) { lock.lock(); _err = err; lock.unlock() }
    var out: Data { lock.lock(); defer { lock.unlock() }; return _out }
    var err: Data { lock.lock(); defer { lock.unlock() }; return _err }
}

/// Reads a process's stdout and stderr pipes to EOF **concurrently**.
///
/// The naïve "wait for the process to exit, then read the pipes" pattern
/// deadlocks: an OS pipe buffers only ~64 KiB, so a child that writes more than
/// that to a stream nobody is draining blocks on `write()` — and therefore never
/// exits, so the waiter waits forever. Draining both streams on separate threads
/// *before* `waitUntilExit()` keeps the buffers empty so the child always makes
/// progress. Shared by every subprocess call site in the app.
enum SubprocessIO {
    static func drainConcurrently(stdout: Pipe, stderr: Pipe) -> (out: Data, err: Data) {
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "dev.echoulen.Aerie.subprocess-drain",
            attributes: .concurrent
        )
        group.enter()
        queue.async {
            outBox.set(stdout.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        queue.async {
            errBox.set(stderr.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.wait()
        return (outBox.data, errBox.data)
    }

    /// Lock-guarded `Data` holder so the two reader closures can publish their
    /// results across threads without tripping the concurrency checker.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Data()
        func set(_ d: Data) { lock.lock(); stored = d; lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return stored }
    }
}
