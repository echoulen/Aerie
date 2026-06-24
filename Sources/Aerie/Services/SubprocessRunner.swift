import Foundation

protocol SubprocessRunner: Sendable {
    /// Returns (stdout, stderr, exitCode). Throws on launch failure only.
    /// `cwd` sets the child's working directory (nil = inherit the parent's).
    func run(_ command: String, _ args: [String], cwd: URL?) async throws -> (String, String, Int32)

    /// Streams stdout line-by-line via `onLine` (each call is one line, no
    /// trailing newline) until EOF, returning the child's exit code. Honors
    /// task cancellation by terminating the child process. stderr is drained
    /// but discarded.
    ///
    /// `onLine` is invoked on an unspecified background thread — callers that
    /// touch `@MainActor`/`@Observable` state must hop to the main actor themselves.
    func stream(
        _ command: String, _ args: [String], cwd: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32
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
    /// Directories searched ahead of the inherited PATH. `~/.local/bin` is where
    /// the Claude Code *native* installer puts `claude` (a symlink into
    /// `~/.local/share/claude/versions/…`); including it lets the GUI resolve the
    /// official binary — and, sitting ahead of `baseDirs`, it wins over a
    /// third-party shim (e.g. a superset/agent wrapper) that merely happens to
    /// appear earlier on the user's shell PATH. Computed (not `let`) because the
    /// home directory is only known at runtime.
    private static var toolDirs: [String] {
        ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
    }
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

    func stream(
        _ command: String, _ args: [String], cwd: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [command] + args
        p.environment = SubprocessPATH.environment()
        if let cwd { p.currentDirectoryURL = cwd }
        let outPipe = Pipe(); p.standardOutput = outPipe
        let errPipe = Pipe(); p.standardError = errPipe

        // Drain stderr so a chatty child can't deadlock on a full stderr pipe.
        DispatchQueue.global().async {
            _ = try? errPipe.fileHandleForReading.readToEnd()
        }

        let buffer = StreamLineBuffer(onLine: onLine)
        let proc = UncheckedBox(p)
        let launch = StreamLaunchState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
                outPipe.fileHandleForReading.readabilityHandler = { fh in
                    let data = fh.availableData
                    if data.isEmpty {
                        fh.readabilityHandler = nil      // EOF
                    } else {
                        buffer.feed(data)
                    }
                }
                p.terminationHandler = { proc in
                    // NOTE: a readabilityHandler invocation already dispatched just
                    // before this nil-assignment may still run after we resume; in
                    // that case availableData is empty (EOF) so it self-nils and is a
                    // no-op. Any late non-empty feed reaches onLine after stream()
                    // returns — downstream (AIReviewStore) ignores lines once the
                    // phase has left .running, so it's harmless.
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    buffer.flush()
                    cont.resume(returning: proc.terminationStatus)
                }
                do {
                    try p.run()
                    if launch.markLaunched() { p.terminate() }   // cancelled before launch finished → kill now
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            if launch.markCancelled() { proc.value.terminate() }  // only terminate a launched process
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

/// Accumulates streamed bytes and emits complete `\n`-terminated lines.
/// Lock-guarded: `readabilityHandler` fires on a background queue.
private final class StreamLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let onLine: @Sendable (String) -> Void
    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        lock.lock()
        pending.append(data)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            let lineData = pending.subdata(in: pending.startIndex..<nl)
            pending.removeSubrange(pending.startIndex...nl)
            if let s = String(data: lineData, encoding: .utf8) { lines.append(s) }
        }
        lock.unlock()
        for l in lines { onLine(l) }
    }

    func flush() {
        lock.lock()
        let rest = pending; pending.removeAll()
        lock.unlock()
        if !rest.isEmpty, let s = String(data: rest, encoding: .utf8), !s.isEmpty { onLine(s) }
    }
}

/// Lets a non-Sendable value (here `Process`) cross into the cancellation
/// handler. We only call `terminate()` on it, which is safe concurrently.
private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ v: T) { value = v }
}

/// Synchronizes process launch with task cancellation so we only ever
/// `terminate()` a process that actually started — regardless of which side
/// wins the race. Both methods return true when the caller should terminate now.
private final class StreamLaunchState: @unchecked Sendable {
    private let lock = NSLock()
    private var launched = false
    private var cancelled = false
    /// Called right after `p.run()` succeeds. Returns true if cancellation
    /// already arrived (so we must terminate now).
    func markLaunched() -> Bool {
        lock.lock(); defer { lock.unlock() }
        launched = true
        return cancelled
    }
    /// Called from the cancellation handler. Returns true if the process is
    /// already launched (so we must terminate now).
    func markCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        return launched
    }
}
