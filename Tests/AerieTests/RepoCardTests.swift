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

    private func makeRepo(name: String = "Aerie", repo: String = "aerie") -> Repository {
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
            hidden: false
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
            RepoCard(row: row, onOpen: {}, onHardReset: {})
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
}
