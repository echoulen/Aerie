import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `DialogMerge` — warning-toned squash-merge
/// confirmation. Two scenarios: ready-to-ship (success CI + approved) and
/// the same fixture seeded with an initial error banner (the failure mode
/// the integration layer flows back into the dialog via `initialError`).
final class DialogMergeTests: XCTestCase {
    private let repoId = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!
    private let accountId = UUID(uuidString: "22222222-0000-0000-0000-000000000002")!
    private let prId = UUID(uuidString: "22222222-0000-0000-0000-000000000003")!
    private let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

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

    private func fixtureAccount() -> GitHubAccount {
        GitHubAccount(id: accountId, login: "carlos-li", host: "github.com")
    }

    private func fixturePR(ci: CIState = .success, review: ReviewState = .approved) -> PullRequest {
        PullRequest(
            id: prId,
            repoId: repoId,
            number: 142,
            title: "Wire the PR card to PRLocalState and add ready-to-ship eyebrow",
            authorLogin: "carlos-li",
            sourceBranch: "feat/phase17-dialogs",
            isMine: true,
            state: .open,
            ciState: ci,
            reviewState: review,
            labels: ["enhancement"],
            htmlUrl: URL(string: "https://github.com/carlos-li/aerie/pull/142")!,
            updatedAt: updatedAt
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

    func test_dialogMerge_readyToShip() {
        let view = DialogMerge(
            pr: fixturePR(),
            repo: fixtureRepo(),
            account: fixtureAccount(),
            onConfirm: { nil },
            onCancel: { }
        )
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }

    func test_dialogMerge_withErrorBanner() {
        let view = DialogMerge(
            pr: fixturePR(),
            repo: fixtureRepo(),
            account: fixtureAccount(),
            onConfirm: { nil },
            onCancel: { },
            initialError: "Merge blocked: required status check \"build\" is failing on the source branch."
        )
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }
}
