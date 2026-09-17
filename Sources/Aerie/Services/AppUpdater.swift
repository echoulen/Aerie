import Foundation

/// Installs a newer Aerie by running the very same `install.sh` that the
/// README's `curl … | bash` one-liner uses. That script already knows how to
/// pick the right architecture's release zip, quit the running app, replace
/// `/Applications/Aerie.app`, strip the quarantine flag, and relaunch —
/// re-implementing any of it in Swift would be a second copy of the tricky
/// part. The Makefile copies the script into the bundle at build time, so the
/// app runs a version it shipped with rather than something fetched from the
/// network at update time.
///
/// Consequence worth knowing: the script targets `/Applications/Aerie.app`
/// regardless of where the running copy lives. `UpdateStore` is what keeps that
/// honest — it only offers an update when the running bundle IS the one in
/// `/Applications` (see `isInstalledInApplications`).
enum AppUpdater {
    enum Failure: Error, LocalizedError, Equatable {
        case scriptMissing
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing:
                return "This build doesn't include the installer. Download the update from GitHub instead."
            case .launchFailed(let message):
                return "Couldn't start the installer: \(message)"
            }
        }
    }

    static let logPath = "/tmp/aerie-update.log"
    /// The installer's exit code lands here once it finishes. The app only
    /// ever sees a non-zero one: a successful install quits Aerie first.
    static let statusPath = "/tmp/aerie-update.status"
    /// How long an install may run before the app stops waiting — a stalled
    /// download never exits on its own.
    static let installTimeout: TimeInterval = 10 * 60
    static let timeoutMessage = "The update didn't finish within 10 minutes — the download may have stalled. Try again."

    /// The installer shipped inside this bundle, or nil for a build assembled
    /// before the Makefile started copying it in.
    static var bundledScript: URL? {
        Bundle.main.url(forResource: "install", withExtension: "sh")
    }

    /// Single-quotes `value` for `/bin/bash`, escaping embedded apostrophes —
    /// an app bundle can sit under a path with spaces or quotes in it.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The one-liner that runs `script` detached from this process. `nohup … &`
    /// is load-bearing: the script's first act is to quit Aerie, so it has to
    /// outlive the app that spawned it. A wrapper shell records the script's
    /// exit code in `status` (cleared first) so the app can notice a failure.
    static func detachedCommand(script: String, log: String = logPath, status: String = statusPath) -> String {
        let inner = "/bin/bash \(shellQuoted(script)) > \(shellQuoted(log)) 2>&1; echo $? > \(shellQuoted(status))"
        return "rm -f \(shellQuoted(status)); nohup /bin/bash -c \(shellQuoted(inner)) > /dev/null 2>&1 &"
    }

    /// A one-line reason for a failed install: the script's own `error: …`
    /// line when it printed one, else its last output line, else the exit code.
    static func failureMessage(exitCode: Int32, log: String) -> String {
        let lines = log.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let error = lines.last(where: { $0.hasPrefix("error:") }) {
            return String(error.dropFirst("error:".count)).trimmingCharacters(in: .whitespaces)
        }
        return lines.last ?? "The installer exited with code \(exitCode)."
    }

    /// Waits for the installer launched by ``run(script:)`` to report back.
    /// Returns a failure message when it exits non-zero or runs past `timeout`,
    /// nil when it exits cleanly (Aerie is being quit and relaunched).
    static func waitForFailure(
        status: String = statusPath, log: String = logPath,
        timeout: TimeInterval = installTimeout, pollInterval: TimeInterval = 1
    ) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOfFile: status, encoding: .utf8),
               let code = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                guard code != 0 else { return nil }
                let logText = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
                return failureMessage(exitCode: code, log: logText)
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Task.isCancelled { return nil }
        }
        return timeoutMessage
    }

    /// Spawns the installer and returns immediately. Nothing to await: the app
    /// keeps running until the script's `quit` reaches it a second later, and
    /// from then on the installer owns the outcome (its log lands at
    /// ``logPath``).
    static func run(script: URL? = bundledScript) throws {
        guard let script else { throw Failure.scriptMissing }
        // Clear a previous attempt's exit code before anything can poll for
        // it — the command's own `rm -f` runs asynchronously in the spawned
        // shell, so a retry could otherwise read the stale failure at once.
        try? FileManager.default.removeItem(atPath: statusPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", detachedCommand(script: script.path)]
        do {
            try process.run()
        } catch {
            throw Failure.launchFailed(error.localizedDescription)
        }
    }
}
