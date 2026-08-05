import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `DialogReset` — danger-toned hard-reset dialog
/// driven by a fixture `Repository` + `LocalGitStatus`. Two scenarios: a
/// dirty+diverged repo (the typical case the dialog exists for) and a
/// clean repo on the default branch (the no-op edge the view still has
/// to render gracefully).
final class DialogResetTests: XCTestCase {
    private let repoId = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    private let accountId = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!
    private let fixedFetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func fixtureRepo() -> Repository {
        Repository(
            id: repoId,
            name: "Aerie",
            localPath: URL(fileURLWithPath: "/Users/dev/work/aerie"),
            githubOwner: "carlos-li",
            githubRepo: "aerie",
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: 0,
            hidden: false
        )
    }

    private func host<V: View>(_ view: V) -> NSHostingView<some View> {
        let frame = ZStack {
            Backdrop()
            view
        }
        .frame(width: 1240, height: 880)
        return NSHostingView(rootView: frame)
    }

    func test_dialogReset_dirtyDiverged() {
        let status = LocalGitStatus(
            repoId: repoId,
            currentBranch: "feat/phase17-dialogs",
            isDirty: true,
            dirtyFileCount: 4,
            aheadOfDefault: 3,
            behindOfDefault: 2,
            unpushedCommits: 3,
            originDefaultSha: "abc1234",
            fetchedAt: fixedFetchedAt
        )
        let view = DialogReset(repo: fixtureRepo(), status: status,
                               onConfirm: { }, onCancel: { })
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }

    func test_dialogReset_cleanOnDefault() {
        let status = LocalGitStatus(
            repoId: repoId,
            currentBranch: "main",
            isDirty: false,
            dirtyFileCount: 0,
            aheadOfDefault: 0,
            behindOfDefault: 0,
            unpushedCommits: 0,
            originDefaultSha: "abc1234",
            fetchedAt: fixedFetchedAt
        )
        let view = DialogReset(repo: fixtureRepo(), status: status,
                               onConfirm: { }, onCancel: { })
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }

    // MARK: - Delete-branch note (non-snapshot)

    func test_deleteBranchNote_nilWhenNotMerged() {
        XCTAssertNil(DialogReset.deleteBranchNote(nil))
    }

    func test_deleteBranchNote_describesBranchAndPR() {
        let info = MergedBranchInfo(
            repoId: repoId, branch: "IOE-3017", prNumber: 62,
            prUrl: URL(string: "https://github.com/carlos-li/aerie/pull/62")!,
            headOid: "deadbeef", mergedAt: fixedFetchedAt)
        XCTAssertEqual(DialogReset.deleteBranchNote(info), "IOE-3017 (merged in #62)")
    }
}
