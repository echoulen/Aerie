import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `RepoCard` across the four visual permutations the
/// Repos view has to handle:
///   1. Clean on default — Hard reset muted.
///   2. Dirty on default — Hard reset amber.
///   3. Diverged + dirty (non-default branch, ahead/behind > 0) — Hard reset amber.
///   4. No cached git status — branch falls back to `repo.defaultBranch`,
///      dirty/clean slot empty.
///
/// Fixed UUIDs are used so the baselines stay deterministic across runs.
final class RepoCardTests: XCTestCase {
    // MARK: - Fixtures

    private let repoId   = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    private let acctId   = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!

    private func makeRepo(name: String = "Aerie", repo: String = "aerie", apiSyncDisabled: Bool = false) -> Repository {
        Repository(
            id: repoId,
            name: name,
            // Deliberately outside any user's $HOME so `collapsedPath`
            // renders the raw path identically on every CI runner.
            localPath: URL(fileURLWithPath: "/opt/repos/aerie"),
            githubOwner: "carlos-li",
            githubRepo: repo,
            defaultBranch: "main",
            primaryAccountId: acctId,
            sortOrder: 0,
            hidden: false,
            apiSyncDisabled: apiSyncDisabled
        )
    }

    private func makeStatus(
        currentBranch: String = "main",
        isDirty: Bool = false,
        dirtyFileCount: Int = 0,
        ahead: Int = 0,
        behind: Int = 0,
        unpushed: Int = 0
    ) -> LocalGitStatus {
        LocalGitStatus(
            repoId: repoId,
            currentBranch: currentBranch,
            isDirty: isDirty,
            dirtyFileCount: dirtyFileCount,
            aheadOfDefault: ahead,
            behindOfDefault: behind,
            unpushedCommits: unpushed,
            originDefaultSha: "deadbeef",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func host(_ row: RepoRow) -> NSHostingView<some View> {
        let view = ZStack {
            Backdrop()
            RepoCard(row: row, onOpen: {})
                .padding(20)
        }
        .frame(width: 980, height: 180)
        return NSHostingView(rootView: view)
    }

    // MARK: - Tests

    func test_repoCard_cleanOnDefault() {
        let row = RepoRow(
            repo: makeRepo(),
            status: makeStatus(currentBranch: "main", isDirty: false)
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 980, height: 180)))
    }

    func test_repoCard_dirtyOnDefault() {
        let row = RepoRow(
            repo: makeRepo(),
            status: makeStatus(
                currentBranch: "main",
                isDirty: true,
                dirtyFileCount: 4
            )
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 980, height: 180)))
    }

    func test_repoCard_diverged() {
        let row = RepoRow(
            repo: makeRepo(),
            status: makeStatus(
                currentBranch: "feat/phase10-repos-view",
                isDirty: true,
                dirtyFileCount: 2,
                ahead: 3,
                behind: 1,
                unpushed: 0
            )
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 980, height: 180)))
    }

    func test_repoCard_noStatus() {
        let row = RepoRow(repo: makeRepo(), status: nil)
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 980, height: 180)))
    }

    // MARK: - Merged-branch logic (non-snapshot)

    private func makeMergedInfo(branch: String = "IOE-3017", number: Int = 62) -> MergedBranchInfo {
        MergedBranchInfo(
            repoId: repoId, branch: branch, prNumber: number,
            prUrl: URL(string: "https://github.com/carlos-li/aerie/pull/\(number)")!,
            headOid: "deadbeef", mergedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func test_resetTitle_defaultWhenNotMerged() {
        let row = RepoRow(repo: makeRepo(), status: makeStatus(currentBranch: "IOE-3017"))
        XCTAssertEqual(RepoCard.resetTitle(row), "Reset to origin/main")
    }

    func test_resetTitle_deleteWhenMerged() {
        var row = RepoRow(repo: makeRepo(), status: makeStatus(currentBranch: "IOE-3017"))
        row.mergedBranch = makeMergedInfo()
        XCTAssertEqual(RepoCard.resetTitle(row), "Reset & delete branch")
    }

    // MARK: - shouldShowCreatePR

    func test_createPR_hidden_whenCleanAndInSync() {
        let row = RepoRow(repo: makeRepo(), status: makeStatus())
        XCTAssertFalse(RepoCard.shouldShowCreatePR(row))
    }

    func test_createPR_hidden_whenNoStatus() {
        let row = RepoRow(repo: makeRepo(), status: nil)
        XCTAssertFalse(RepoCard.shouldShowCreatePR(row))
    }

    func test_createPR_shown_whenDirty() {
        let row = RepoRow(repo: makeRepo(), status: makeStatus(isDirty: true, dirtyFileCount: 1))
        XCTAssertTrue(RepoCard.shouldShowCreatePR(row))
    }

    func test_createPR_shown_whenAhead() {
        let row = RepoRow(repo: makeRepo(), status: makeStatus(ahead: 2))
        XCTAssertTrue(RepoCard.shouldShowCreatePR(row))
    }

    func test_createPR_shown_whenUnpushed() {
        let row = RepoRow(repo: makeRepo(), status: makeStatus(unpushed: 1))
        XCTAssertTrue(RepoCard.shouldShowCreatePR(row))
    }

    func test_createPR_shown_whenOffDefaultBranch() {
        let row = RepoRow(repo: makeRepo(), status: makeStatus(currentBranch: "feat/x"))
        XCTAssertTrue(RepoCard.shouldShowCreatePR(row))
    }

    func test_createPR_hidden_whenBranchAlreadyMerged() {
        let merged = MergedBranchInfo(
            repoId: repoId, branch: "feat/x", prNumber: 5,
            prUrl: URL(string: "https://github.com/e/r/pull/5")!,
            headOid: "deadbeef", mergedAt: Date(timeIntervalSince1970: 1))
        let row = RepoRow(repo: makeRepo(),
                          status: makeStatus(currentBranch: "feat/x", ahead: 1),
                          mergedBranch: merged)
        XCTAssertFalse(RepoCard.shouldShowCreatePR(row))
    }

    // MARK: - API sync toggle

    func test_apiSyncToggleIcon_pauseWhenActive() {
        let row = RepoRow(repo: makeRepo(apiSyncDisabled: false), status: makeStatus())
        XCTAssertEqual(RepoCard.apiSyncToggleIcon(row), "pause.circle")
    }

    func test_apiSyncToggleIcon_playWhenDisabled() {
        let row = RepoRow(repo: makeRepo(apiSyncDisabled: true), status: makeStatus())
        XCTAssertEqual(RepoCard.apiSyncToggleIcon(row), "play.circle")
    }

    func test_apiSyncToggleHelp_reflectsState() {
        let active = RepoRow(repo: makeRepo(apiSyncDisabled: false), status: makeStatus())
        let paused = RepoRow(repo: makeRepo(apiSyncDisabled: true), status: makeStatus())
        XCTAssertEqual(RepoCard.apiSyncToggleHelp(active), "Pause API sync (PR / Issue)")
        XCTAssertEqual(RepoCard.apiSyncToggleHelp(paused), "Resume API sync")
    }
}
