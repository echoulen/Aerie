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

    /// Reported bug: a PR with a *failing* CI rollup still lit the Merge button
    /// when GitHub reported UNSTABLE (the failing checks aren't
    /// branch-protection-required, so GitHub itself would allow the merge).
    /// Aerie deliberately refuses to offer a one-click merge over red CI — a
    /// hard failure blocks the button regardless of `mergeStateStatus`.
    func test_isMergeable_unstableButFailingCI_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .failure, review: .approved, mergeStateStatus: "UNSTABLE")))
    }

    func test_isMergeable_cleanButFailingCI_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .failure, review: .approved, mergeStateStatus: "CLEAN")))
    }

    func test_isMergeable_blockedMergeState_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .success, review: .approved, mergeStateStatus: "BLOCKED")))
    }

    /// Reported bug (PR #797): GitHub reports BEHIND — the head branch is out of
    /// date with its base and the repo requires up-to-date branches, so GitHub
    /// itself refuses the merge until the branch is updated. Aerie was lumping
    /// BEHIND in with the mergeable states and lighting the Merge button; the
    /// PUT then fails with a 405. BEHIND must block the button.
    func test_isMergeable_behindMergeState_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .success, review: .approved, mergeStateStatus: "BEHIND")))
    }

    /// Reported bug (PR #797, follow-up): right after a one-click "Update
    /// branch", GitHub is still recomputing mergeability and briefly returns
    /// UNKNOWN. The permissive fallback treated UNKNOWN as a green light and lit
    /// the Merge button — even though the PR was actually still BLOCKED (a
    /// required review). When GitHub explicitly can't determine the state we
    /// must NOT offer a one-click merge.
    func test_isMergeable_unknownMergeState_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .success, review: .reviewRequired, mergeStateStatus: "UNKNOWN")))
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

    // MARK: - mergeBlockReason
    //
    // `isMergeable` is now a thin wrapper over `PullRequest.mergeBlockReason`,
    // the single source of truth shared by the Merge button (cached row) and
    // the pre-merge re-validation (fresh server row). The reason string is what
    // the merge dialog surfaces when a stale-cache merge is refused, so it has
    // to name something the user can act on.

    func test_mergeBlockReason_clean_isNil() {
        XCTAssertNil(makePR(ci: .success, review: .reviewRequired, mergeStateStatus: "CLEAN").mergeBlockReason)
    }

    func test_mergeBlockReason_blocked_namesBranchProtectionOrReview() {
        let reason = makePR(ci: .success, review: .reviewRequired, mergeStateStatus: "BLOCKED").mergeBlockReason
        let lower = (reason ?? "").lowercased()
        XCTAssertTrue(
            lower.contains("branch protection") || lower.contains("review"),
            "BLOCKED should explain it's branch-protection/required-review; got: \(reason ?? "nil")"
        )
    }

    func test_mergeBlockReason_dirty_mentionsConflicts() {
        let reason = makePR(mergeStateStatus: "DIRTY").mergeBlockReason
        XCTAssertEqual(reason?.lowercased().contains("conflict"), true, "got: \(reason ?? "nil")")
    }

    func test_mergeBlockReason_failingCI_mentionsCI() {
        let reason = makePR(ci: .failure, mergeStateStatus: "CLEAN").mergeBlockReason
        XCTAssertEqual(reason?.contains("CI"), true, "got: \(reason ?? "nil")")
    }

    func test_mergeBlockReason_behind_mentionsOutOfDateOrUpdate() {
        let reason = makePR(ci: .success, review: .approved, mergeStateStatus: "BEHIND").mergeBlockReason
        let lower = (reason ?? "").lowercased()
        XCTAssertTrue(
            lower.contains("out of date") || lower.contains("update"),
            "BEHIND should say the branch is out of date / needs updating; got: \(reason ?? "nil")"
        )
    }

    func test_mergeBlockReason_unknown_mentionsComputingOrRefresh() {
        let reason = makePR(ci: .success, review: .reviewRequired, mergeStateStatus: "UNKNOWN").mergeBlockReason
        let lower = (reason ?? "").lowercased()
        XCTAssertTrue(
            lower.contains("computing") || lower.contains("refresh"),
            "UNKNOWN should say the state is still being computed; got: \(reason ?? "nil")"
        )
    }

    /// The `nil` fallback (no `mergeStateStatus` — older cached rows) stays
    /// permissive: it must NOT be swept up by the new UNKNOWN block. A plain
    /// open PR with passing/no CI and no explicit "changes requested" still
    /// merges.
    func test_mergeBlockReason_nilStatus_staysPermissive() {
        XCTAssertNil(makePR(ci: .success, review: .reviewRequired, mergeStateStatus: nil).mergeBlockReason)
    }

    func test_mergeBlockReason_isMergeable_agreeWithGate() {
        // The wrapper and the reason must never disagree.
        let blocked = makePR(ci: .success, review: .approved, mergeStateStatus: "BLOCKED")
        XCTAssertNotNil(blocked.mergeBlockReason)
        XCTAssertFalse(PRCard.isMergeable(blocked))

        let clean = makePR(ci: .success, review: .reviewRequired, mergeStateStatus: "CLEAN")
        XCTAssertNil(clean.mergeBlockReason)
        XCTAssertTrue(PRCard.isMergeable(clean))
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

    // Local signal — the checked-out branch is behind its base. A PR with no
    // `mergeStateStatus` isolates this from the GitHub signal below.

    func test_updateBranch_shownWhenBehind() {
        XCTAssertTrue(PRCard.shouldShowUpdateBranch(makePR(), makeLocal(behind: 2)))
    }

    func test_updateBranch_hiddenWhenLevel() {
        XCTAssertFalse(PRCard.shouldShowUpdateBranch(makePR(), makeLocal(behind: 0)))
    }

    /// When the PR's branch isn't the current checkout, `behind` is nil and
    /// GitHub reports nothing special — neither signal fires, so no pill.
    func test_updateBranch_hiddenWhenNotCheckedOut() {
        XCTAssertFalse(PRCard.shouldShowUpdateBranch(
            makePR(),
            makeLocal(isCurrentBranch: false, ahead: nil, behind: nil, unpushed: nil)
        ))
    }

    func test_updateBranch_hiddenWhenNoLocalState() {
        XCTAssertFalse(PRCard.shouldShowUpdateBranch(makePR(), nil))
    }

    // GitHub signal — `mergeStateStatus == "BEHIND"`. The reported bug (PR
    // #797): the branch isn't checked out, so the local signal can't fire, yet
    // GitHub blocks the merge until the branch is updated. The pill must show
    // off the authoritative state alone.

    func test_updateBranch_shownWhenGitHubBehind_evenIfNotCheckedOut() {
        XCTAssertTrue(PRCard.shouldShowUpdateBranch(makePR(mergeStateStatus: "BEHIND"), nil))
    }

    func test_updateBranch_shownWhenGitHubBehind_evenIfLocalLevel() {
        XCTAssertTrue(PRCard.shouldShowUpdateBranch(makePR(mergeStateStatus: "BEHIND"), makeLocal(behind: 0)))
    }

    func test_updateBranch_hiddenWhenGitHubClean() {
        XCTAssertFalse(PRCard.shouldShowUpdateBranch(makePR(mergeStateStatus: "CLEAN"), nil))
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

    /// Not-checked-out BEHIND PRs have no local count, so the tooltip drops the
    /// number rather than claiming "0 new commits".
    func test_updateBranchTooltip_unknownCount_isCountFree() {
        XCTAssertEqual(
            UpdateBranchButton.tooltip(behind: nil),
            "Update this branch with the latest changes from origin/main"
        )
        XCTAssertEqual(
            UpdateBranchButton.tooltip(behind: 0),
            "Update this branch with the latest changes from origin/main"
        )
    }
}
