import XCTest
import GRDB
@testable import Aerie

final class WorktreeMergeToolTests: XCTestCase {
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
    /// Returns (mainPath, worktreePath). Worktree on branch `feat/wt`, base `main`
    /// advanced by one commit so a merge has something to fast-forward.
    private func makeRepoWithWorktree() throws -> (URL, URL) {
        let main = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        tempURLs.append(main)
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try shell(["git", "-C", main.path, "init", "-q", "-b", "main"])
        try shell(["git", "-C", main.path, "config", "user.email", "t@t"])
        try shell(["git", "-C", main.path, "config", "user.name", "T"])
        try "x".write(to: main.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try shell(["git", "-C", main.path, "add", "."])
        try shell(["git", "-C", main.path, "commit", "-q", "-m", "init"])
        // origin = main itself (so origin/main resolves for updateBranchFromBase).
        try shell(["git", "-C", main.path, "remote", "add", "origin", main.path])
        try shell(["git", "-C", main.path, "fetch", "-q", "origin"])
        let wt = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        tempURLs.append(wt)
        try shell(["git", "-C", main.path, "worktree", "add", "-q", "-b", "feat/wt", wt.path])
        return (main, wt)
    }

    func test_handle_mergesWorktree() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let (main, wt) = try makeRepoWithWorktree()
        let repo = Repository(id: UUID(), name: "R", localPath: main, githubOwner: "o", githubRepo: "r",
                              defaultBranch: "main", primaryAccountId: acct, sortOrder: 0, hidden: false)
        try await db.repos.insert(repo)
        let tool = WorktreeMergeTool(db: db, git: LiveGitService(), accountToken: { _ in nil }, refresh: { _ in })

        let result = try await tool.handle(params: .object([
            "repo_id": .string(repo.id.uuidString), "worktree_path": .string(wt.path),
        ]))
        guard case .object(let obj) = result else { return XCTFail("expected object") }
        XCTAssertEqual(obj["merged"], .bool(true))
    }

    func test_handle_foreignPath_throwsInvalidParams() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let (main, _) = try makeRepoWithWorktree()
        let repo = Repository(id: UUID(), name: "R", localPath: main, githubOwner: "o", githubRepo: "r",
                              defaultBranch: "main", primaryAccountId: acct, sortOrder: 0, hidden: false)
        try await db.repos.insert(repo)
        let tool = WorktreeMergeTool(db: db, git: LiveGitService(), accountToken: { _ in nil }, refresh: { _ in })
        do {
            _ = try await tool.handle(params: .object([
                "repo_id": .string(repo.id.uuidString),
                "worktree_path": .string("/tmp/not-a-worktree-\(UUID().uuidString)"),
            ]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isTrue() throws {
        let db = try makeDB()
        let tool = WorktreeMergeTool(db: db, git: LiveGitService(), accountToken: { _ in nil }, refresh: { _ in })
        XCTAssertTrue(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_worktree_merge")
    }
}
