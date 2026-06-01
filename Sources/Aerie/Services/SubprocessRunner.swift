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
            p.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: (out, err, proc.terminationStatus))
            }
        }
    }
}
