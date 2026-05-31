import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for PRCard across the four visual permutations the
/// design has to handle (mergeable + mine, mergeable + not mine, not
/// mergeable, and missing local state).
///
/// Both `updatedAt` and `now` are fixed `Date(timeIntervalSince1970:)`
/// values so the relative-time string stays stable across runs.
final class PRCardTests: XCTestCase {
    // MARK: - Fixtures

    private let fixedNow = Date(timeIntervalSince1970: 1_700_010_000) // 2h 46m after updatedAt below
    private let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRepo(name: String = "Aerie") -> Repository {
        Repository(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!,
            name: name,
            localPath: URL(fileURLWithPath: "/tmp/aerie"),
            githubOwner: "carlos-li",
            githubRepo: "aerie",
            defaultBranch: "main",
            primaryAccountId: UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!,
            sortOrder: 0,
            hidden: false
        )
    }

    private func makePR(
        number: Int = 142,
        title: String = "Wire the PR card to PRLocalState and add ready-to-ship eyebrow",
        author: String = "octocat",
        isMine: Bool = true,
        ci: CIState = .success,
        review: ReviewState = .approved,
        sourceBranch: String = "feat/phase9-prs-view",
        mergeStateStatus: String? = nil
    ) -> PullRequest {
        PullRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000cc")!,
            repoId: UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!,
            number: number,
            title: title,
            authorLogin: author,
            sourceBranch: sourceBranch,
            isMine: isMine,
            state: .open,
            ciState: ci,
            reviewState: review,
            labels: ["enhancement"],
            htmlUrl: URL(string: "https://github.com/carlos-li/aerie/pull/\(number)")!,
            updatedAt: updatedAt,
            mergeStateStatus: mergeStateStatus
        )
    }

    private func host(_ row: PRRow) -> NSHostingView<some View> {
        let view = ZStack {
            Backdrop()
            PRCard(row: row, onMerge: {}, onOpen: {}, now: fixedNow)
                .padding(20)
        }
        .frame(width: 980, height: 280)
        return NSHostingView(rootView: view)
    }

    // MARK: - Tests

    func test_prCard_mergeable_yours() {
        let row = PRRow(
            pr: makePR(isMine: true),
            repo: makeRepo(),
            localState: PRLocalState(
                prId: UUID(),
                sourceBranch: "feat/phase9-prs-view",
                localBranchExists: true,
                isCurrentBranch: true,
                dirty: false,
                ahead: 2,
                behind: 0,
                unpushed: 1
            )
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 980, height: 280)))
    }

    func test_prCard_mergeable_notYours() {
        let row = PRRow(
            pr: makePR(author: "another-dev", isMine: false),
            repo: makeRepo(),
            localState: PRLocalState(
                prId: UUID(),
                sourceBranch: "feat/phase9-prs-view",
                localBranchExists: true,
                isCurrentBranch: false,
                dirty: nil,
                ahead: nil,
                behind: nil,
                unpushed: nil
            )
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 980, height: 280)))
    }

    func test_prCard_notMergeable_failingCI() {
        let row = PRRow(
            pr: makePR(
                author: "another-dev",
                isMine: false,
                ci: .failure,
                review: .reviewRequired
            ),
            repo: makeRepo(),
            localState: PRLocalState(
                prId: UUID(),
                sourceBranch: "feat/phase9-prs-view",
                localBranchExists: true,
                isCurrentBranch: true,
                dirty: true,
                ahead: 3,
                behind: 1,
                unpushed: 0
            )
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 980, height: 280)))
    }

    func test_prCard_noLocalState() {
        let row = PRRow(
            pr: makePR(isMine: true),
            repo: makeRepo(),
            localState: nil
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 980, height: 240)))
    }

    // MARK: - isMergeable heuristic

    // Authoritative path — trust GitHub's `mergeStateStatus` when present.

    /// The reported bug: GitHub reports the PR CLEAN (nothing blocking the
    /// merge), but the button rendered disabled because the heuristic demanded
    /// an explicit approval. Repos without required reviews merge fine, so a
    /// CLEAN state must light the button regardless of review state.
    func test_isMergeable_cleanMergeState_isMergeable() {
        XCTAssertTrue(PRCard.isMergeable(makePR(ci: .none, review: .reviewRequired, mergeStateStatus: "CLEAN")))
    }

    func test_isMergeable_unstableMergeState_isMergeable() {
        // Non-required checks still running, but GitHub allows the merge.
        XCTAssertTrue(PRCard.isMergeable(makePR(ci: .pending, review: .reviewRequired, mergeStateStatus: "UNSTABLE")))
    }

    func test_isMergeable_blockedMergeState_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .success, review: .approved, mergeStateStatus: "BLOCKED")))
    }

    func test_isMergeable_dirtyConflicts_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .success, review: .approved, mergeStateStatus: "DIRTY")))
    }

    func test_isMergeable_draft_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .success, review: .approved, mergeStateStatus: "DRAFT")))
    }

    // Fallback path — no `mergeStateStatus` yet (older cache / still computing):
    // open and not actively blocked. Approval is NOT required.

    func test_isMergeable_fallback_notApprovedNoChecks_isMergeable() {
        XCTAssertTrue(PRCard.isMergeable(makePR(ci: .none, review: .reviewRequired)))
    }

    func test_isMergeable_fallback_approvedPassingCI_isMergeable() {
        XCTAssertTrue(PRCard.isMergeable(makePR(ci: .success, review: .approved)))
    }

    func test_isMergeable_fallback_failingCI_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .failure, review: .approved)))
    }

    func test_isMergeable_fallback_pendingCI_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .pending, review: .approved)))
    }

    func test_isMergeable_fallback_changesRequested_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .success, review: .changesRequested)))
    }

    // MARK: - Update-branch pill visibility

    private func makeLocal(
        isCurrentBranch: Bool = true,
        ahead: Int? = 0,
        behind: Int? = 0,
        unpushed: Int? = 0
    ) -> PRLocalState {
        PRLocalState(
            prId: UUID(),
            sourceBranch: "feat/x",
            localBranchExists: true,
            isCurrentBranch: isCurrentBranch,
            dirty: false,
            ahead: ahead,
            behind: behind,
            unpushed: unpushed
        )
    }

    func test_updateBranch_shownWhenBehind() {
        XCTAssertTrue(PRCard.shouldShowUpdateBranch(makeLocal(behind: 2)))
    }

    func test_updateBranch_hiddenWhenLevel() {
        XCTAssertFalse(PRCard.shouldShowUpdateBranch(makeLocal(behind: 0)))
    }

    /// When the PR's branch isn't the current checkout, `behind` is nil — the
    /// pill (and the local merge it triggers) only make sense on the checkout.
    func test_updateBranch_hiddenWhenNotCheckedOut() {
        XCTAssertFalse(PRCard.shouldShowUpdateBranch(
            makeLocal(isCurrentBranch: false, ahead: nil, behind: nil, unpushed: nil)
        ))
    }

    func test_updateBranch_hiddenWhenNoLocalState() {
        XCTAssertFalse(PRCard.shouldShowUpdateBranch(nil))
    }

    // MARK: - Update-branch tooltip (pluralised commit count)

    func test_updateBranchTooltip_singular() {
        XCTAssertEqual(
            UpdateBranchButton.tooltip(behind: 1),
            "Update this branch with 1 new commit from origin/main"
        )
    }

    func test_updateBranchTooltip_plural() {
        XCTAssertEqual(
            UpdateBranchButton.tooltip(behind: 3),
            "Update this branch with 3 new commits from origin/main"
        )
    }
}
