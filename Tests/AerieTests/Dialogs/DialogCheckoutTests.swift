import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Unit coverage for `CheckoutPlan.make` — the pure logic that decides whether a
/// force-checkout is destructive, whether the repo is already current, and which
/// local items would be discarded. Mirrors the design's `aerieCheckoutPlan`.
final class DialogCheckoutTests: XCTestCase {
    private func local(
        isCurrentBranch: Bool = true,
        dirty: Bool? = false,
        ahead: Int? = 0,
        behind: Int? = 0,
        unpushed: Int? = 0
    ) -> PRLocalState {
        PRLocalState(
            prId: UUID(),
            sourceBranch: "feat/x",
            localBranchExists: true,
            isCurrentBranch: isCurrentBranch,
            dirty: dirty,
            ahead: ahead,
            behind: behind,
            unpushed: unpushed
        )
    }

    func test_plan_cleanCheckedOutInSync_isSafeAndCurrent() {
        let p = CheckoutPlan.make(for: local())
        XCTAssertFalse(p.destructive)
        XCTAssertTrue(p.current)
        XCTAssertTrue(p.losses.isEmpty)
    }

    func test_plan_dirty_isDestructive() {
        let p = CheckoutPlan.make(for: local(dirty: true))
        XCTAssertTrue(p.destructive)
        XCTAssertFalse(p.current)
        XCTAssertEqual(p.losses, ["uncommitted working-tree changes"])
    }

    func test_plan_aheadAndUnpushed_pluralised() {
        let p = CheckoutPlan.make(for: local(dirty: false, ahead: 2, unpushed: 3))
        XCTAssertTrue(p.destructive)
        XCTAssertEqual(p.losses, ["2 local commits ahead of origin", "3 unpushed commits"])
    }

    func test_plan_aheadAndUnpushed_singular() {
        let p = CheckoutPlan.make(for: local(dirty: false, ahead: 1, unpushed: 1))
        XCTAssertEqual(p.losses, ["1 local commit ahead of origin", "1 unpushed commit"])
    }

    func test_plan_behindButClean_isSafeButNotCurrent() {
        // Behind is not itself a loss (the checkout moves forward), so it isn't
        // destructive — but the repo isn't "current" while it's behind.
        let p = CheckoutPlan.make(for: local(dirty: false, ahead: 0, behind: 2, unpushed: 0))
        XCTAssertFalse(p.destructive)
        XCTAssertFalse(p.current)
        XCTAssertTrue(p.losses.isEmpty)
    }

    func test_plan_notCheckedOut_isSafeButNotCurrent() {
        let p = CheckoutPlan.make(for: local(
            isCurrentBranch: false, dirty: nil, ahead: nil, behind: nil, unpushed: nil
        ))
        XCTAssertFalse(p.destructive)
        XCTAssertFalse(p.current)
    }

    func test_plan_nilLocal_isSafeNotCurrent() {
        let p = CheckoutPlan.make(for: nil)
        XCTAssertFalse(p.destructive)
        XCTAssertFalse(p.current)
        XCTAssertTrue(p.losses.isEmpty)
    }

    // MARK: - Snapshots

    private func fixtureRepo() -> Repository {
        Repository(
            id: UUID(uuidString: "22222222-0000-0000-0000-000000000001")!,
            name: "web-portal",
            localPath: URL(fileURLWithPath: "/Users/dev/work/web-portal"),
            githubOwner: "acme-co",
            githubRepo: "web-portal",
            defaultBranch: "main",
            primaryAccountId: UUID(uuidString: "22222222-0000-0000-0000-000000000002")!,
            sortOrder: 0,
            hidden: false
        )
    }

    private func fixturePR() -> PullRequest {
        PullRequest(
            id: UUID(uuidString: "22222222-0000-0000-0000-000000000003")!,
            repoId: UUID(uuidString: "22222222-0000-0000-0000-000000000001")!,
            number: 42,
            title: "feat: add SSO login to the web portal",
            authorLogin: "octocat",
            sourceBranch: "feat/sso-login",
            isMine: true,
            state: .open,
            ciState: .failure,
            reviewState: .approved,
            labels: [],
            htmlUrl: URL(string: "https://github.com/acme-co/web-portal/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
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

    func test_dialogCheckout_destructive() {
        let view = DialogCheckout(
            repo: fixtureRepo(),
            pr: fixturePR(),
            local: local(isCurrentBranch: true, dirty: true, ahead: 2, behind: 0, unpushed: 1),
            onConfirm: { }, onCancel: { }
        )
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }

    func test_dialogCheckout_safeCurrent() {
        let view = DialogCheckout(
            repo: fixtureRepo(),
            pr: fixturePR(),
            local: local(isCurrentBranch: true, dirty: false, ahead: 0, behind: 0, unpushed: 0),
            onConfirm: { }, onCancel: { }
        )
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }
}
