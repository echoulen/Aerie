import XCTest
@testable import Aerie

final class WorktreeParsingTests: XCTestCase {
    private let main = URL(fileURLWithPath: "/Users/me/work/aerie")

    func testFiltersMainCheckoutAndKeepsExtras() {
        let porcelain = """
        worktree /Users/me/work/aerie
        HEAD c23a9955c0ffee00c23a9955c0ffee00c23a9955
        branch refs/heads/main

        worktree /Users/me/.superset/worktrees/3f2a91c/review
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/review/pr-142
        """
        let got = WorktreeParsing.parse(porcelain: porcelain, mainWorktreePath: main)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].branchLabel, "review/pr-142")
        XCTAssertFalse(got[0].isDetached)
        XCTAssertFalse(got[0].prunable)
        XCTAssertEqual(got[0].path.path, "/Users/me/.superset/worktrees/3f2a91c/review")
    }

    func testDetachedUsesShortSha() {
        let porcelain = """
        worktree /Users/me/work/aerie
        HEAD aaaa
        branch refs/heads/main

        worktree /Users/me/code/aerie-wt/release-check
        HEAD a91f3c2deadbeefa91f3c2deadbeefa91f3c2dead
        detached
        """
        let got = WorktreeParsing.parse(porcelain: porcelain, mainWorktreePath: main)
        XCTAssertEqual(got.count, 1)
        XCTAssertTrue(got[0].isDetached)
        XCTAssertEqual(got[0].branchLabel, "a91f3c2")
    }

    func testPrunableFlagged() {
        let porcelain = """
        worktree /Users/me/work/aerie
        HEAD aaaa
        branch refs/heads/main

        worktree /Users/me/.superset/worktrees/55ad0e2/hotfix
        HEAD bbbb
        branch refs/heads/hotfix/tls
        prunable gitdir file points to non-existent location
        """
        let got = WorktreeParsing.parse(porcelain: porcelain, mainWorktreePath: main)
        XCTAssertEqual(got.count, 1)
        XCTAssertTrue(got[0].prunable)
    }

    func testBareRepoSkipped() {
        // Two records: the main checkout (filtered out by path) and a separate
        // `bare` worktree (dropped by the !bare guard). Result must be empty —
        // this exercises the bare-skip path, not just the main-path filter.
        let porcelain = """
        worktree /Users/me/work/aerie
        HEAD aaaa
        branch refs/heads/main

        worktree /Users/me/bare-clone
        HEAD bbbb
        bare
        """
        XCTAssertTrue(WorktreeParsing.parse(porcelain: porcelain, mainWorktreePath: main).isEmpty)
    }

    func testSourceInference() {
        XCTAssertEqual(
            WorktreeSource.infer(from: URL(fileURLWithPath: "/Users/me/.superset/worktrees/x/y")),
            .superset)
        XCTAssertEqual(
            WorktreeSource.infer(from: URL(fileURLWithPath: "/Users/me/code/wt")),
            .manual)
    }
}

extension WorktreeParsingTests {
    func testLiveListingFindsExtraWorktree() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("aerie-wt-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func git(_ args: [String], in dir: URL) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git", "-C", dir.path] + args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try p.run(); p.waitUntilExit()
        }

        let mainRepo = root.appendingPathComponent("main")
        try fm.createDirectory(at: mainRepo, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: mainRepo)
        try git(["-c", "user.email=t@t", "-c", "user.name=t",
                 "commit", "-q", "--allow-empty", "-m", "init"], in: mainRepo)
        let wt = root.appendingPathComponent("feature")
        try git(["worktree", "add", "-q", "-b", "feature", wt.path], in: mainRepo)

        let svc = LiveGitService()
        let rows = await svc.worktrees(mainWorktreeAt: mainRepo)
        XCTAssertEqual(rows.map(\.branchLabel), ["feature"])
        XCTAssertFalse(rows[0].isDirty)
    }
}
