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
    /// outlive the app that spawned it. Pure + static so the quoting is
    /// testable without spawning anything.
    static func detachedCommand(script: String, log: String = logPath) -> String {
        "nohup /bin/bash \(shellQuoted(script)) > \(shellQuoted(log)) 2>&1 &"
    }

    /// Spawns the installer and returns immediately. Nothing to await: the app
    /// keeps running until the script's `quit` reaches it a second later, and
    /// from then on the installer owns the outcome (its log lands at
    /// ``logPath``).
    static func run(script: URL? = bundledScript) throws {
        guard let script else { throw Failure.scriptMissing }
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
