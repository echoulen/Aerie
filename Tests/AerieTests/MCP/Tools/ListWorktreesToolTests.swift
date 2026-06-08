import XCTest
import GRDB
@testable import Aerie

final class ListWorktreesToolTests: XCTestCase {
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
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "shell", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: out])
        }
        return out
    }
    /// A repo with one extra worktree on branch `feat/wt`. Returns the main path.
    private func makeRepoWithWorktree() throws -> URL {
        let main = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        tempURLs.append(main)
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try shell(["git", "-C", main.path, "init", "-q", "-b", "main"])
        try "x".write(to: main.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try shell(["git", "-C", main.path, "add", "."])
        try shell(["git", "-C", main.path, "-c", "user.email=t@t", "-c", "user.name=T", "commit", "-q", "-m", "init"])
        let wt = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        tempURLs.append(wt)
        try shell(["git", "-C", main.path, "worktree", "add", "-q", "-b", "feat/wt", wt.path])
        return main
    }

    func test_handle_listsExtraWorktree() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let main = try makeRepoWithWorktree()
        let repo = Repository(id: UUID(), name: "R", localPath: main, githubOwner: "o", githubRepo: "r",
                              defaultBranch: "main", primaryAccountId: acct, sortOrder: 0, hidden: false)
        try await db.repos.insert(repo)

        let tool = ListWorktreesTool(db: db, git: LiveGitService())
        let result = try await tool.handle(params: .object(["repo_id": .string(repo.id.uuidString)]))

        guard case .object(let obj) = result, case .array(let items) = obj["worktrees"] ?? .null else {
            return XCTFail("expected .worktrees array, got \(result)")
        }
        XCTAssertEqual(items.count, 1)
        guard case .object(let wt) = items[0] else { return XCTFail("worktree not an object") }
        XCTAssertEqual(wt["branch_label"], .string("feat/wt"))
        XCTAssertEqual(wt["is_detached"], .bool(false))
    }

    func test_handle_unknownRepo_throwsInvalidParams() async throws {
        let db = try makeDB()
        let tool = ListWorktreesTool(db: db, git: LiveGitService())
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(UUID().uuidString)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isFalse() throws {
        let db = try makeDB()
        let tool = ListWorktreesTool(db: db, git: LiveGitService())
        XCTAssertFalse(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_list_worktrees")
    }
}
