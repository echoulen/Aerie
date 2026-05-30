import XCTest
@testable import Aerie

final class RepoDetectorTests: XCTestCase {
    // MARK: - Helpers

    private var tempDirs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempDirs {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirs.removeAll()
    }

    private func makeTempRepo(origin: String) throws -> URL {
        let dir = URL(
            fileURLWithPath: NSTemporaryDirectory()
                .appending(UUID().uuidString),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)

        // git init
        try runShell(["git", "init", "-q", "-b", "main"], in: dir)
        // identity config so commit succeeds without inheriting global config
        try runShell(["git", "config", "user.email", "test@example.com"], in: dir)
        try runShell(["git", "config", "user.name", "Tester"], in: dir)
        // initial commit
        let readme = dir.appendingPathComponent("README.md")
        try "hello".write(to: readme, atomically: true, encoding: .utf8)
        try runShell(["git", "add", "README.md"], in: dir)
        try runShell(["git", "commit", "-q", "-m", "init"], in: dir)
        // origin
        try runShell(["git", "remote", "add", "origin", origin], in: dir)
        return dir
    }

    @discardableResult
    private func runShell(_ args: [String], in dir: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.currentDirectoryURL = dir
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        p.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Parser tests

    func test_parseGitHubOrigin_ssh() {
        let parsed = RepoDetector.parseGitHubOrigin("git@github.com:foo/bar.git")
        XCTAssertEqual(parsed?.host, "github.com")
        XCTAssertEqual(parsed?.owner, "foo")
        XCTAssertEqual(parsed?.repo, "bar")
    }

    func test_parseGitHubOrigin_sshNoSuffix() {
        let parsed = RepoDetector.parseGitHubOrigin("git@github.com:foo/bar")
        XCTAssertEqual(parsed?.host, "github.com")
        XCTAssertEqual(parsed?.owner, "foo")
        XCTAssertEqual(parsed?.repo, "bar")
    }

    func test_parseGitHubOrigin_https() {
        let parsed = RepoDetector.parseGitHubOrigin("https://github.com/foo/bar")
        XCTAssertEqual(parsed?.host, "github.com")
        XCTAssertEqual(parsed?.owner, "foo")
        XCTAssertEqual(parsed?.repo, "bar")
    }

    func test_parseGitHubOrigin_httpsWithGit() {
        let parsed = RepoDetector.parseGitHubOrigin("https://github.com/foo/bar.git")
        XCTAssertEqual(parsed?.host, "github.com")
        XCTAssertEqual(parsed?.owner, "foo")
        XCTAssertEqual(parsed?.repo, "bar")
    }

    func test_parseGitHubOrigin_gheHttps() {
        let parsed = RepoDetector.parseGitHubOrigin("https://my.ghe.com/team/proj.git")
        XCTAssertEqual(parsed?.host, "my.ghe.com")
        XCTAssertEqual(parsed?.owner, "team")
        XCTAssertEqual(parsed?.repo, "proj")
    }

    func test_parseGitHubOrigin_garbage() {
        XCTAssertNil(RepoDetector.parseGitHubOrigin("not-a-url"))
        XCTAssertNil(RepoDetector.parseGitHubOrigin(""))
        XCTAssertNil(RepoDetector.parseGitHubOrigin("file:///tmp/foo"))
    }

    // MARK: - End-to-end detect

    func test_detect_returnsDetectedRepo_forValidLocalRepo() async throws {
        let dir = try makeTempRepo(origin: "git@github.com:test/repo.git")
        let detector = RepoDetector()
        let result = try await detector.detect(at: dir, accounts: [])

        XCTAssertEqual(result.githubOwner, "test")
        XCTAssertEqual(result.githubRepo, "repo")
        XCTAssertEqual(result.host, "github.com")
        XCTAssertEqual(result.currentBranch, "main")
        XCTAssertFalse(result.isDirty)
        XCTAssertNil(result.suggestedAccountId)
    }

    func test_detect_suggestsAccountByHost() async throws {
        let dir = try makeTempRepo(origin: "https://my.ghe.com/team/proj.git")

        let gheAccount = GitHubAccount(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!,
            login: "internal-bot",
            host: "my.ghe.com"
        )
        let comAccount = GitHubAccount(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000002")!,
            login: "carlos-li",
            host: "github.com"
        )

        let detector = RepoDetector()
        let result = try await detector.detect(at: dir, accounts: [comAccount, gheAccount])

        XCTAssertEqual(result.host, "my.ghe.com")
        XCTAssertEqual(result.suggestedAccountId, gheAccount.id)
    }

    /// Regression: when several accounts share a host (e.g. multiple
    /// github.com logins), the suggestion must prefer the account whose login
    /// matches the repo **owner** — not merely the first host match. Binding a
    /// repo to an account that can't access it (a private repo owned by a
    /// different login) left the PRs/Issues lists silently empty.
    func test_detect_prefersAccountMatchingOwner_amongSameHostAccounts() async throws {
        let dir = try makeTempRepo(origin: "git@github.com:echoulen/Aerie.git")

        let botAccount = GitHubAccount(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            login: "Jarvis-E",
            host: "github.com"
        )
        let ownerAccount = GitHubAccount(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!,
            login: "echoulen",
            host: "github.com"
        )

        let detector = RepoDetector()
        // botAccount is listed first — host-only matching would wrongly pick it.
        let result = try await detector.detect(at: dir, accounts: [botAccount, ownerAccount])

        XCTAssertEqual(result.suggestedAccountId, ownerAccount.id)
    }

    /// Owner matching is case-insensitive (GitHub logins are), so an origin
    /// owner of `Echoulen` still binds to the `echoulen` account.
    func test_detect_ownerMatchIsCaseInsensitive() async throws {
        let dir = try makeTempRepo(origin: "git@github.com:Echoulen/Aerie.git")
        let ownerAccount = GitHubAccount(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!,
            login: "echoulen",
            host: "github.com"
        )
        let detector = RepoDetector()
        let result = try await detector.detect(at: dir, accounts: [ownerAccount])
        XCTAssertEqual(result.suggestedAccountId, ownerAccount.id)
    }

    /// When no account login matches the owner (e.g. an org-owned repo), fall
    /// back to the first account on the same host — preserving prior behaviour.
    func test_detect_fallsBackToHost_whenNoOwnerMatch() async throws {
        let dir = try makeTempRepo(origin: "git@github.com:some-org/proj.git")
        let a = GitHubAccount(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000004")!,
            login: "carlos-li",
            host: "github.com"
        )
        let detector = RepoDetector()
        let result = try await detector.detect(at: dir, accounts: [a])
        XCTAssertEqual(result.suggestedAccountId, a.id)
    }

    func test_detect_marksDirty_whenWorkingTreeHasChanges() async throws {
        let dir = try makeTempRepo(origin: "git@github.com:test/repo.git")
        // Make a dirty file
        try "edit".write(
            to: dir.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let detector = RepoDetector()
        let result = try await detector.detect(at: dir, accounts: [])
        XCTAssertTrue(result.isDirty)
    }
}
