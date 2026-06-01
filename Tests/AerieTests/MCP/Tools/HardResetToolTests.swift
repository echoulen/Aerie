import XCTest
import GRDB
@testable import Aerie

final class HardResetToolTests: XCTestCase {
    // MARK: - Helpers

    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    @discardableResult
    private func insertAccount(_ db: AppDatabase, id: UUID = UUID(), login: String = "tester") throws -> UUID {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [id.uuidString, login, "github.com"]
            )
        }
        return id
    }

    /// Shell helper: runs a process synchronously, capturing combined
    /// stdout+stderr. Throws on non-zero exit. Mirrors `GitServiceTests`.
    @discardableResult
    private func shell(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
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

    /// Build a clone diverged from origin/main: own branch, one local
    /// commit, and a dirty file. Returns the working tree URL.
    private func makeDivergedClone() throws -> URL {
        let remoteDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + "-remote.git")
        tempURLs.append(remoteDir)
        try shell(["git", "init", "-q", "--bare", "-b", "main", remoteDir.path])

        let seedDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        tempURLs.append(seedDir)
        try FileManager.default.createDirectory(at: seedDir, withIntermediateDirectories: true)
        try shell(["git", "-C", seedDir.path, "init", "-q", "-b", "main"])
        try shell(["git", "-C", seedDir.path, "remote", "add", "origin", remoteDir.path])
        try "hi".write(to: seedDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try shell(["git", "-C", seedDir.path, "add", "."])
        try shell([
            "git", "-C", seedDir.path,
            "-c", "user.email=t@t",
            "-c", "user.name=T",
            "commit", "-q", "-m", "init",
        ])
        try shell(["git", "-C", seedDir.path, "push", "-q", "-u", "origin", "main"])

        let cloneDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        tempURLs.append(cloneDir)
        try shell(["git", "clone", "-q", remoteDir.path, cloneDir.path])
        try shell(["git", "-C", cloneDir.path, "config", "user.email", "t@t"])
        try shell(["git", "-C", cloneDir.path, "config", "user.name", "T"])
        try shell(["git", "-C", cloneDir.path, "checkout", "-q", "-b", "feat/lost"])
        try "lost".write(
            to: cloneDir.appendingPathComponent("lost.txt"),
            atomically: true, encoding: .utf8
        )
        try shell(["git", "-C", cloneDir.path, "add", "."])
        try shell([
            "git", "-C", cloneDir.path,
            "-c", "user.email=t@t",
            "-c", "user.name=T",
            "commit", "-q", "-m", "lost",
        ])
        // Dirty the working tree.
        try "dirty".write(
            to: cloneDir.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )
        return cloneDir
    }

    final class RefreshSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _ids: [UUID] = []
        var ids: [UUID] {
            lock.lock(); defer { lock.unlock() }
            return _ids
        }
        func record(_ id: UUID) {
            lock.lock(); defer { lock.unlock() }
            _ids.append(id)
        }
    }

    // MARK: - Tests

    func test_handle_resetsCloneAndReturnsSummary() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let clone = try makeDivergedClone()
        let repo = Repository(
            id: UUID(),
            name: "Example",
            localPath: clone,
            githubOwner: "octocat",
            githubRepo: "hello-world",
            defaultBranch: "main",
            primaryAccountId: acct,
            sortOrder: 0,
            hidden: false
        )
        try await db.repos.insert(repo)

        let git = LiveGitService()
        let spy = RefreshSpy()
        let tool = HardResetTool(db: db, git: git, refresh: { id in spy.record(id) }, accountToken: { _ in nil })

        let result = try await tool.handle(
            params: .object(["repo_id": .string(repo.id.uuidString)])
        )

        guard case .object(let obj) = result else {
            XCTFail("expected .object, got \(result)")
            return
        }
        // 1 dirty file (a.txt), 1 ahead-of-main commit (lost.txt).
        XCTAssertEqual(obj["discarded_dirty_files"], .int(1))
        XCTAssertEqual(obj["discarded_commits"], .int(1))

        // Working tree clean post-reset.
        let postStatus = try shell([
            "git", "-C", clone.path, "status", "--porcelain",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(postStatus, "")

        let postBranch = try shell([
            "git", "-C", clone.path, "symbolic-ref", "--short", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(postBranch, "main")

        // Refresh fired exactly once with the repo id.
        for _ in 0..<50 {
            if spy.ids.count == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(spy.ids, [repo.id])
    }

    func test_handle_unknownRepo_throwsInvalidParams() async throws {
        let db = try makeDB()
        let tool = HardResetTool(db: db, git: LiveGitService(), refresh: { _ in }, accountToken: { _ in nil })
        do {
            _ = try await tool.handle(
                params: .object(["repo_id": .string(UUID().uuidString)])
            )
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_handle_invalidPath_throwsMinus32011() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = Repository(
            id: UUID(),
            name: "Bogus",
            localPath: URL(fileURLWithPath: "/nonexistent/aerie-test-\(UUID().uuidString)"),
            githubOwner: "octocat",
            githubRepo: "hello-world",
            defaultBranch: "main",
            primaryAccountId: acct,
            sortOrder: 0,
            hidden: false
        )
        try await db.repos.insert(repo)

        let tool = HardResetTool(db: db, git: LiveGitService(), refresh: { _ in }, accountToken: { _ in nil })
        do {
            _ = try await tool.handle(
                params: .object(["repo_id": .string(repo.id.uuidString)])
            )
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32011)
        }
    }

    func test_isWrite_isTrue() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        let db = try! AppDatabase(url: url)
        let tool = HardResetTool(db: db, git: LiveGitService(), refresh: { _ in }, accountToken: { _ in nil })
        XCTAssertTrue(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_hard_reset_to_default")
    }
}
