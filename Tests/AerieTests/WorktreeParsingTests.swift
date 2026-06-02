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
