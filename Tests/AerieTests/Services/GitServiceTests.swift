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

    /// Build a temp repo backed by a bare "origin" remote so we can simulate
    /// ahead/behind/unpushed scenarios end-to-end. The clone tracks origin/main.
    /// Returns the clone's working tree URL.
    private func makeTempRepoWithOrigin() throws -> URL {
        let remoteDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + "-remote.git")
        try shell([
            "git", "init", "-q", "--bare", "-b", "main", remoteDir.path,
        ])

        let workTree = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: workTree, withIntermediateDirectories: true
        )
        try shell(["git", "-C", workTree.path, "init", "-q", "-b", "main"])
        try shell([
            "git", "-C", workTree.path,
            "remote", "add", "origin", remoteDir.path,
        ])
        try "hi".write(
            to: workTree.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )
        try shell(["git", "-C", workTree.path, "add", "."])
        try shell([
            "git", "-C", workTree.path,
            "-c", "user.email=t@t",
            "-c", "user.name=T",
            "commit", "-q", "-m", "init",
        ])
        try shell([
            "git", "-C", workTree.path,
            "push", "-q", "-u", "origin", "main",
        ])
        return workTree
    }

    /// Add a commit on the current branch in `repo` containing a file
    /// `<name>.txt`. Useful for advancing branches in ahead/behind tests.
    private func addCommit(
        in repo: URL, file name: String, body: String = "x"
    ) throws {
        try body.write(
            to: repo.appendingPathComponent("\(name).txt"),
            atomically: true, encoding: .utf8
        )
        try shell(["git", "-C", repo.path, "add", "."])
        try shell([
            "git", "-C", repo.path,
            "-c", "user.email=t@t",
            "-c", "user.name=T",
            "commit", "-q", "-m", name,
        ])
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

    // MARK: - Task 5.2: ahead / behind / unpushed

    func test_readStatus_aheadBehindUnpushed_againstOrigin() async throws {
        // Two clones from the same bare remote let us put `origin/main`
        // two commits ahead of the clone we measure, and our clone two
        // commits ahead of origin (one unpushed).
        let remoteDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + "-remote.git")
        try shell([
            "git", "init", "-q", "--bare", "-b", "main", remoteDir.path,
        ])

        // Seed the remote via a helper clone.
        let seedDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: seedDir, withIntermediateDirectories: true
        )
        try shell(["git", "-C", seedDir.path, "init", "-q", "-b", "main"])
        try shell([
            "git", "-C", seedDir.path,
            "remote", "add", "origin", remoteDir.path,
        ])
        try "hi".write(
            to: seedDir.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )
        try shell(["git", "-C", seedDir.path, "add", "."])
        try shell([
            "git", "-C", seedDir.path,
            "-c", "user.email=t@t",
            "-c", "user.name=T",
            "commit", "-q", "-m", "init",
        ])
        try shell([
            "git", "-C", seedDir.path,
            "push", "-q", "-u", "origin", "main",
        ])

        // Clone (our target) — currently in sync with origin.
        let cloneDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try shell([
            "git", "clone", "-q", remoteDir.path, cloneDir.path,
        ])
        try shell([
            "git", "-C", cloneDir.path,
            "config", "user.email", "t@t",
        ])
        try shell([
            "git", "-C", cloneDir.path,
            "config", "user.name", "T",
        ])

        // Advance origin by 1 commit (via the seed clone push).
        try addCommit(in: seedDir, file: "seed1")
        try shell(["git", "-C", seedDir.path, "push", "-q"])

        // Fetch on the clone so origin/main is updated locally, but DON'T pull.
        try shell(["git", "-C", cloneDir.path, "fetch", "-q"])

        // Add 2 local commits on the clone — these are ahead and unpushed.
        try addCommit(in: cloneDir, file: "local1")
        try addCommit(in: cloneDir, file: "local2")

        let svc = LiveGitService()
        let status = try await svc.readStatus(at: cloneDir, repoId: UUID())

        XCTAssertEqual(status.currentBranch, "main")
        XCTAssertEqual(status.aheadOfDefault, 2)
        XCTAssertEqual(status.behindOfDefault, 1)
        XCTAssertEqual(status.unpushedCommits, 2)
    }

    func test_readStatus_noUpstream_unpushedReturnsZero() async throws {
        // Local-only repo: no remote, no upstream. Should be 0, not throw.
        let repo = try makeTempRepo()
        let svc = LiveGitService()
        let status = try await svc.readStatus(at: repo, repoId: UUID())
        XCTAssertEqual(status.aheadOfDefault, 0)
        XCTAssertEqual(status.behindOfDefault, 0)
        XCTAssertEqual(status.unpushedCommits, 0)
    }

    // MARK: - Task 5.3: default branch detection + originDefaultSha

    func test_readStatus_originDefaultSha_populatedFromOriginMain() async throws {
        // Clone of a bare remote — `origin/HEAD` will point at refs/remotes/origin/main
        // because we cloned with -b main. originDefaultSha should be the
        // 7-char short SHA of origin/main.
        let workTree = try makeTempRepoWithOrigin()

        // After push above, the seed clone IS the work tree. Clone again so
        // we get a real clone with origin/HEAD set up.
        let remoteURL = try shell([
            "git", "-C", workTree.path,
            "remote", "get-url", "origin",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let cloneDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try shell([
            "git", "clone", "-q", remoteURL, cloneDir.path,
        ])

        let expectedShort = try shell([
            "git", "-C", cloneDir.path,
            "rev-parse", "--short", "origin/main",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let svc = LiveGitService()
        let status = try await svc.readStatus(at: cloneDir, repoId: UUID())
        XCTAssertEqual(status.originDefaultSha, expectedShort)
        XCTAssertEqual(status.currentBranch, "main")
    }

    func test_readStatus_defaultBranch_fallsBackToMaster() async throws {
        // Bare remote on `master` plus a clone. We deliberately remove
        // origin/HEAD so detection has to walk down the fallback chain to
        // refs/remotes/origin/master.
        let remoteDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + "-remote.git")
        try shell([
            "git", "init", "-q", "--bare", "-b", "master", remoteDir.path,
        ])

        let seedDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: seedDir, withIntermediateDirectories: true
        )
        try shell(["git", "-C", seedDir.path, "init", "-q", "-b", "master"])
        try shell([
            "git", "-C", seedDir.path,
            "remote", "add", "origin", remoteDir.path,
        ])
        try "hi".write(
            to: seedDir.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )
        try shell(["git", "-C", seedDir.path, "add", "."])
        try shell([
            "git", "-C", seedDir.path,
            "-c", "user.email=t@t",
            "-c", "user.name=T",
            "commit", "-q", "-m", "init",
        ])
        try shell([
            "git", "-C", seedDir.path,
            "push", "-q", "-u", "origin", "master",
        ])

        let cloneDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try shell(["git", "clone", "-q", remoteDir.path, cloneDir.path])

        // Drop origin/HEAD so we hit the master fallback path.
        try shell([
            "git", "-C", cloneDir.path,
            "symbolic-ref", "--delete", "refs/remotes/origin/HEAD",
        ])

        // origin/master exists and ahead/behind should resolve against it.
        // We can verify default-branch detection indirectly via the short SHA.
        let expectedShort = try shell([
            "git", "-C", cloneDir.path,
            "rev-parse", "--short", "origin/master",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let svc = LiveGitService()
        let status = try await svc.readStatus(at: cloneDir, repoId: UUID())
        XCTAssertEqual(status.originDefaultSha, expectedShort)
        XCTAssertEqual(status.currentBranch, "master")
    }

    func test_readStatus_defaultBranch_noOriginFallsBackEmpty() async throws {
        // Local-only repo, no origin. originDefaultSha should be "" and
        // ahead/behind should be 0 (no ref to compare against).
        let repo = try makeTempRepo()
        let svc = LiveGitService()
        let status = try await svc.readStatus(at: repo, repoId: UUID())
        XCTAssertEqual(status.originDefaultSha, "")
        XCTAssertEqual(status.aheadOfDefault, 0)
        XCTAssertEqual(status.behindOfDefault, 0)
    }
}
