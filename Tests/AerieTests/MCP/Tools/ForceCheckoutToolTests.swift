import XCTest
import GRDB
@testable import Aerie

final class ForceCheckoutToolTests: XCTestCase {
    private var tempURLs: [URL] = []
    override func tearDownWithError() throws {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs.removeAll()
    }
    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }
    @discardableResult
    private func insertAccount(_ db: AppDatabase, id: UUID = UUID()) throws -> UUID {
        try db.dbQueue.write { c in
            try c.execute(sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                          arguments: [id.uuidString, "tester", "github.com"])
        }
        return id
    }
    @discardableResult
    private func shell(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "shell", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: out])
        }
        return out
    }
    /// Clone with origin carrying an extra branch `feat/x`. Returns the clone path.
    private func makeCloneWithRemoteBranch() throws -> URL {
        let remote = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + "-remote.git")
        tempURLs.append(remote)
        try shell(["git", "init", "-q", "--bare", "-b", "main", remote.path])
        let seed = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        tempURLs.append(seed)
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try shell(["git", "-C", seed.path, "init", "-q", "-b", "main"])
        try shell(["git", "-C", seed.path, "remote", "add", "origin", remote.path])
        try "hi".write(to: seed.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try shell(["git", "-C", seed.path, "add", "."])
        try shell(["git", "-C", seed.path, "-c", "user.email=t@t", "-c", "user.name=T", "commit", "-q", "-m", "init"])
        try shell(["git", "-C", seed.path, "push", "-q", "-u", "origin", "main"])
        try shell(["git", "-C", seed.path, "checkout", "-q", "-b", "feat/x"])
        try "feat".write(to: seed.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try shell(["git", "-C", seed.path, "add", "."])
        try shell(["git", "-C", seed.path, "-c", "user.email=t@t", "-c", "user.name=T", "commit", "-q", "-m", "feat"])
        try shell(["git", "-C", seed.path, "push", "-q", "-u", "origin", "feat/x"])
        let clone = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        tempURLs.append(clone)
        try shell(["git", "clone", "-q", remote.path, clone.path])
        try shell(["git", "-C", clone.path, "config", "user.email", "t@t"])
        try shell(["git", "-C", clone.path, "config", "user.name", "T"])
        return clone
    }
    final class RefreshSpy: @unchecked Sendable {
        private let lock = NSLock(); private var _ids: [UUID] = []
        var ids: [UUID] { lock.lock(); defer { lock.unlock() }; return _ids }
        func record(_ id: UUID) { lock.lock(); defer { lock.unlock() }; _ids.append(id) }
    }

    func test_handle_checksOutBranchAndRefreshes() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let clone = try makeCloneWithRemoteBranch()
        let repo = Repository(id: UUID(), name: "R", localPath: clone, githubOwner: "o", githubRepo: "r",
                              defaultBranch: "main", primaryAccountId: acct, sortOrder: 0, hidden: false)
        try await db.repos.insert(repo)
        let spy = RefreshSpy()
        let tool = ForceCheckoutTool(db: db, git: LiveGitService(), accountToken: { _ in nil }, refresh: { spy.record($0) })

        let result = try await tool.handle(params: .object([
            "repo_id": .string(repo.id.uuidString), "branch": .string("feat/x"),
        ]))
        guard case .object(let obj) = result else { return XCTFail("expected object") }
        XCTAssertEqual(obj["checked_out"], .string("feat/x"))
        let head = try shell(["git", "-C", clone.path, "symbolic-ref", "--short", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(head, "feat/x")
        for _ in 0..<50 { if spy.ids.count == 1 { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(spy.ids, [repo.id])
    }

    func test_handle_unknownRepo_throwsInvalidParams() async throws {
        let db = try makeDB()
        let tool = ForceCheckoutTool(db: db, git: LiveGitService(), accountToken: { _ in nil }, refresh: { _ in })
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(UUID().uuidString), "branch": .string("x")]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_handle_missingBranch_throwsInvalidParams() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = Repository(id: UUID(), name: "R", localPath: URL(fileURLWithPath: "/tmp/r"), githubOwner: "o",
                              githubRepo: "r", defaultBranch: "main", primaryAccountId: acct, sortOrder: 0, hidden: false)
        try await db.repos.insert(repo)
        let tool = ForceCheckoutTool(db: db, git: LiveGitService(), accountToken: { _ in nil }, refresh: { _ in })
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(repo.id.uuidString)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isTrue() throws {
        let db = try makeDB()
        let tool = ForceCheckoutTool(db: db, git: LiveGitService(), accountToken: { _ in nil }, refresh: { _ in })
        XCTAssertTrue(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_force_checkout")
    }
}
