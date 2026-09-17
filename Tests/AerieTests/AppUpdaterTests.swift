import XCTest
@testable import Aerie

final class AppUpdaterTests: XCTestCase {
    func test_shellQuoted_wrapsInSingleQuotes() {
        XCTAssertEqual(AppUpdater.shellQuoted("/Applications/Aerie.app"),
                       "'/Applications/Aerie.app'")
    }

    func test_shellQuoted_survivesSpacesAndApostrophes() {
        XCTAssertEqual(AppUpdater.shellQuoted("/Users/carlos' apps/Aerie.app"),
                       "'/Users/carlos'\\'' apps/Aerie.app'")
    }

    /// The command must background the script (it quits Aerie, so it has to
    /// outlive the app), capture its log, and record its exit code so the app
    /// can tell a failed install from one still running. Run it for real with
    /// paths containing spaces and an apostrophe to prove the quoting holds.
    func test_detachedCommand_runsInBackground_capturesLogAndExitCode() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aerie update's \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("install.sh")
        try "echo 'Downloading…'\necho 'error: boom' >&2\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
        let log = dir.appendingPathComponent("update.log").path
        let status = dir.appendingPathComponent("update.status").path
        try "stale".write(toFile: status, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", AppUpdater.detachedCommand(script: script.path, log: log, status: status)]
        try process.run()
        process.waitUntilExit()

        var code: String?
        for _ in 0..<50 {
            if let s = try? String(contentsOfFile: status, encoding: .utf8), s != "stale" {
                code = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if code?.isEmpty == false { break }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(code, "3")
        let logText = try String(contentsOfFile: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("error: boom"))
    }

    func test_failureMessage_prefersTheInstallersErrorLine() {
        let log = "Downloading latest Aerie (arm64)…\nerror: Couldn't download https://x — is there a published release?\n"
        XCTAssertEqual(AppUpdater.failureMessage(exitCode: 1, log: log),
                       "Couldn't download https://x — is there a published release?")
    }

    func test_failureMessage_fallsBackToTheLastLine_thenTheExitCode() {
        XCTAssertEqual(AppUpdater.failureMessage(exitCode: 6, log: "Downloading…\ncurl: (6) Could not resolve host\n\n"),
                       "curl: (6) Could not resolve host")
        XCTAssertEqual(AppUpdater.failureMessage(exitCode: 2, log: ""),
                       "The installer exited with code 2.")
    }

    func test_waitForFailure_reportsANonZeroExit() async throws {
        let (status, log) = try tempFiles()
        try "1\n".write(toFile: status, atomically: true, encoding: .utf8)
        try "error: boom\n".write(toFile: log, atomically: true, encoding: .utf8)
        let message = await AppUpdater.waitForFailure(status: status, log: log, timeout: 5, pollInterval: 0.01)
        XCTAssertEqual(message, "boom")
    }

    func test_waitForFailure_successReportsNothing() async throws {
        let (status, log) = try tempFiles()
        try "0\n".write(toFile: status, atomically: true, encoding: .utf8)
        let message = await AppUpdater.waitForFailure(status: status, log: log, timeout: 5, pollInterval: 0.01)
        XCTAssertNil(message)
    }

    /// A download that stalls never exits; the app must stop spinning anyway.
    func test_waitForFailure_timesOutWhenTheInstallerNeverFinishes() async throws {
        let (status, log) = try tempFiles()
        let message = await AppUpdater.waitForFailure(status: status, log: log, timeout: 0.1, pollInterval: 0.01)
        XCTAssertEqual(message, AppUpdater.timeoutMessage)
    }

    private func tempFiles() throws -> (status: String, log: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return (dir.appendingPathComponent("status").path, dir.appendingPathComponent("log").path)
    }

    func test_run_withoutABundledScript_reportsScriptMissing() {
        XCTAssertThrowsError(try AppUpdater.run(script: nil)) { error in
            XCTAssertEqual(error as? AppUpdater.Failure, .scriptMissing)
        }
    }
}
