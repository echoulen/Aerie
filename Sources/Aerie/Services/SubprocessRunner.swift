import Foundation

protocol SubprocessRunner: Sendable {
    /// Returns (stdout, stderr, exitCode). Throws on launch failure only.
    func run(_ command: String, _ args: [String]) async throws -> (String, String, Int32)
}

struct LiveSubprocessRunner: SubprocessRunner {
    func run(_ command: String, _ args: [String]) async throws -> (String, String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [command] + args
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
