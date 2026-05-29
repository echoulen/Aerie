import XCTest
import GRDB
@testable import Aerie

/// Tests the polling pipeline's per-repo refresh seam: find repo → readStatus →
/// upsert cache. This is the unit that was missing entirely (issue #30) — the
/// scheduler's refresh closure was a no-op, so nothing ever populated
/// `gitStatusCache` and every repo card fell back to its default branch.
final class GitStatusRefresherTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
    }

    // MARK: - Fixtures

    /// Run a command via `/usr/bin/env`, capturing combined stdout+stderr.
    /// Throws on non-zero exit. Mirrors `GitServiceTests.shell`.
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

    /// Fresh temp git repo with one commit on `main`. Returns its working tree.
    private func makeTempRepo() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        tempURLs.append(url)
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
            "-c", "user.email=t@t", "-c", "user.name=T",
            "commit", "-q", "-m", "init",
        ])
        return url
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    @discardableResult
    private func insertAccount(_ db: AppDatabase) throws -> UUID {
        let id = UUID()
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [id.uuidString, "tester", "github.com"]
            )
        }
        return id
    }

    @discardableResult
    private func insertRepo(
        _ db: AppDatabase, accountId: UUID, localPath: URL
    ) async throws -> Repository {
        let r = Repository(
            id: UUID(),
            name: localPath.lastPathComponent,
            localPath: localPath,
            githubOwner: "octocat",
            githubRepo: "hello-world",
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: 0,
            hidden: false
        )
        try await db.repos.insert(r)
        return r
    }

    // MARK: - Core repro (issue #30)

    func test_refresh_populatesCacheWithActualBranchAndDirtyState() async throws {
        // A repo checked out off the default branch with a dirty working tree —
        // exactly the situation that wrongly rendered "main / Clean".
        let repoURL = try makeTempRepo()
        try shell(["git", "-C", repoURL.path, "checkout", "-q", "-b", "feat/x"])
        try "hi\nmore".write(
            to: repoURL.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )

        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct, localPath: repoURL)

        // Sanity: cache is empty before refresh.
        let before = try await db.gitStatusCache.status(forRepo: repo.id)
        XCTAssertNil(before)

        let refresher = GitStatusRefresher(db: db, gitService: LiveGitService())
        await refresher.refresh(repoId: repo.id)

        let after = try await db.gitStatusCache.status(forRepo: repo.id)
        let status = try XCTUnwrap(after, "refresh should populate the cache")
        XCTAssertEqual(status.currentBranch, "feat/x")
        XCTAssertTrue(status.isDirty)
        XCTAssertEqual(status.dirtyFileCount, 1)
        XCTAssertEqual(status.repoId, repo.id)
    }

    // MARK: - Robustness

    func test_refresh_unknownRepoId_doesNotThrowAndLeavesCacheEmpty() async throws {
        let db = try makeDB()
        let refresher = GitStatusRefresher(db: db, gitService: LiveGitService())

        // No repo with this id exists — refresh must be a no-op, not a crash.
        await refresher.refresh(repoId: UUID())

        let cached = try await db.gitStatusCache.status(forRepo: UUID())
        XCTAssertNil(cached)
    }

    func test_refresh_nonGitPath_doesNotThrowAndLeavesCacheEmpty() async throws {
        // A tracked repo whose localPath isn't a git working tree (moved/deleted).
        let notARepo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        tempURLs.append(notARepo)
        try FileManager.default.createDirectory(
            at: notARepo, withIntermediateDirectories: true
        )

        let db = try makeDB()
        let acct = try insertAccount(db)
        let repo = try await insertRepo(db, accountId: acct, localPath: notARepo)

        let refresher = GitStatusRefresher(db: db, gitService: LiveGitService())
        await refresher.refresh(repoId: repo.id)

        let cached = try await db.gitStatusCache.status(forRepo: repo.id)
        XCTAssertNil(cached, "a non-git path should leave the cache untouched")
    }
}
