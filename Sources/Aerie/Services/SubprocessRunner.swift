import Foundation

protocol SubprocessRunner: Sendable {
    /// Returns (stdout, stderr, exitCode). Throws on launch failure only.
    func run(_ command: String, _ args: [String]) async throws -> (String, String, Int32)
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
    func run(_ command: String, _ args: [String]) async throws -> (String, String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [command] + args
        p.environment = SubprocessPATH.environment()
        let outPipe = Pipe(); p.standardOutput = outPipe
        let errPipe = Pipe(); p.standardError  = errPipe
        try p.run()
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                // Drain both pipes concurrently *before* waiting for exit. Reading
                // them only once the process has terminated (the previous
                // `terminationHandler` approach) deadlocks the moment a child
                // writes more than the OS pipe buffer (~64 KiB) to a stream
                // nobody is draining: it blocks on `write()` and never exits, so
                // the handler never fires. See `SubprocessIO.drainConcurrently`.
                let (outData, errData) = SubprocessIO.drainConcurrently(
                    stdout: outPipe, stderr: errPipe
                )
                p.waitUntilExit()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                cont.resume(returning: (out, err, p.terminationStatus))
            }
        }
    }
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
