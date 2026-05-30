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
        sourceBranch: String = "feat/phase9-prs-view"
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
            updatedAt: updatedAt
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

    /// The reported bug: an approved PR with **no required checks** (`ci .none`)
    /// is mergeable on GitHub, but the Merge button rendered disabled because
    /// the heuristic demanded `ci == .success`. No checks must not block.
    func test_isMergeable_approvedWithNoChecks_isMergeable() {
        XCTAssertTrue(PRCard.isMergeable(makePR(ci: .none, review: .approved)))
    }

    func test_isMergeable_approvedWithPassingCI_isMergeable() {
        XCTAssertTrue(PRCard.isMergeable(makePR(ci: .success, review: .approved)))
    }

    func test_isMergeable_failingCI_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .failure, review: .approved)))
    }

    func test_isMergeable_pendingCI_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .pending, review: .approved)))
    }

    func test_isMergeable_notApproved_isNotMergeable() {
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .none, review: .reviewRequired)))
        XCTAssertFalse(PRCard.isMergeable(makePR(ci: .success, review: .changesRequested)))
    }
}
