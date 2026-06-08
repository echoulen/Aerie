import XCTest
import GRDB
@testable import Aerie

final class DiscardUnstagedToolTests: XCTestCase {
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
    private func makeDirtyRepo() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        tempURLs.append(dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try shell(["git", "-C", dir.path, "init", "-q", "-b", "main"])
        try "hi".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try shell(["git", "-C", dir.path, "add", "."])
        try shell(["git", "-C", dir.path, "-c", "user.email=t@t", "-c", "user.name=T", "commit", "-q", "-m", "init"])
        // Make it dirty: modify tracked + add untracked.
        try "dirty".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "new".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        return dir
    }
    final class RefreshSpy: @unchecked Sendable {
        private let lock = NSLock(); private var _ids: [UUID] = []
        var ids: [UUID] { lock.lock(); defer { lock.unlock() }; return _ids }
        func record(_ id: UUID) { lock.lock(); defer { lock.unlock() }; _ids.append(id) }
    }

    func test_handle_cleansWorkingTree() async throws {
        let db = try makeDB()
        let acct = try insertAccount(db)
        let dir = try makeDirtyRepo()
        let repo = Repository(id: UUID(), name: "R", localPath: dir, githubOwner: "o", githubRepo: "r",
                              defaultBranch: "main", primaryAccountId: acct, sortOrder: 0, hidden: false)
        try await db.repos.insert(repo)
        let spy = RefreshSpy()
        let tool = DiscardUnstagedTool(db: db, git: LiveGitService(), refresh: { spy.record($0) })

        let result = try await tool.handle(params: .object(["repo_id": .string(repo.id.uuidString)]))
        guard case .object(let obj) = result else { return XCTFail("expected object") }
        XCTAssertEqual(obj["discarded"], .bool(true))
        let status = try shell(["git", "-C", dir.path, "status", "--porcelain"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(status, "")
        for _ in 0..<50 { if spy.ids.count == 1 { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(spy.ids, [repo.id])
    }

    func test_handle_unknownRepo_throwsInvalidParams() async throws {
        let db = try makeDB()
        let tool = DiscardUnstagedTool(db: db, git: LiveGitService(), refresh: { _ in })
        do {
            _ = try await tool.handle(params: .object(["repo_id": .string(UUID().uuidString)]))
            XCTFail("expected throw")
        } catch let e as JSONRPCError {
            XCTAssertEqual(e.code, -32602)
        }
    }

    func test_isWrite_isTrue() throws {
        let db = try makeDB()
        let tool = DiscardUnstagedTool(db: db, git: LiveGitService(), refresh: { _ in })
        XCTAssertTrue(tool.isWrite)
        XCTAssertEqual(tool.name, "aerie_discard_unstaged")
    }
}
