import XCTest
@testable import Aerie

final class GitServiceTests: XCTestCase {
    // MARK: - Fixtures

    /// Shell helper. Runs `git` (or anything else on PATH via `/usr/bin/env`)
    /// synchronously, capturing combined stdout+stderr. Throws on non-zero exit.
    @discardableResult
    private func shell(_ args: [String], in dir: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        if let dir = dir { p.currentDirectoryURL = dir }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(
                domain: "shell", code: Int(p.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: out]
            )
        }
        return out
    }

    /// Build a fresh temp git repo with a single committed file and initial
    /// branch `main`. Returns the working-tree URL.
    private func makeTempRepo() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        try shell(["git", "-C", url.path, "init", "-q", "-b", "main"])
        try "hi".write(
            to: url.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )
        try shell(["git", "-C", url.path, "add", "."])
        try shell([
            "git", "-C", url.path,
            "-c", "user.email=t@t",
            "-c", "user.name=T",
            "commit", "-q", "-m", "init",
        ])
        return url
    }

    // MARK: - Tests

    func test_readStatus_returnsCleanForFreshCommit() async throws {
        let repo = try makeTempRepo()
        let svc = LiveGitService()
        let status = try await svc.readStatus(at: repo, repoId: UUID())
        XCTAssertFalse(status.isDirty)
        XCTAssertEqual(status.dirtyFileCount, 0)
        XCTAssertEqual(status.currentBranch, "main")
        XCTAssertEqual(status.aheadOfDefault, 0)
        XCTAssertEqual(status.behindOfDefault, 0)
        XCTAssertEqual(status.unpushedCommits, 0)
        XCTAssertEqual(status.originDefaultSha, "")
    }

    func test_readStatus_dirtyAfterEdit() async throws {
        let repo = try makeTempRepo()
        try "hi\nmore".write(
            to: repo.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )
        let svc = LiveGitService()
        let status = try await svc.readStatus(at: repo, repoId: UUID())
        XCTAssertTrue(status.isDirty)
        XCTAssertEqual(status.dirtyFileCount, 1)
    }

    func test_readStatus_dirtyForUntrackedFile() async throws {
        let repo = try makeTempRepo()
        try "new".write(
            to: repo.appendingPathComponent("b.txt"),
            atomically: true, encoding: .utf8
        )
        let svc = LiveGitService()
        let status = try await svc.readStatus(at: repo, repoId: UUID())
        XCTAssertTrue(status.isDirty)
        XCTAssertEqual(status.dirtyFileCount, 1)
    }

    func test_readStatus_propagatesRepoId() async throws {
        let repo = try makeTempRepo()
        let id = UUID()
        let svc = LiveGitService()
        let status = try await svc.readStatus(at: repo, repoId: id)
        XCTAssertEqual(status.repoId, id)
    }
}
