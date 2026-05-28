import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `DialogSignOut`. The affected-repos path is the
/// higher-value scenario (it's the warning the dialog exists for); the
/// empty-list copy is verified via static text in `DialogSignOut.swift`.
final class DialogSignOutTests: XCTestCase {
    private let accountId = UUID(uuidString: "33333333-0000-0000-0000-000000000001")!

    private func makeRepo(name: String, owner: String, repo: String) -> Repository {
        Repository(
            id: UUID(),
            name: name,
            localPath: URL(fileURLWithPath: "/Users/dev/work/\(name)"),
            githubOwner: owner,
            githubRepo: repo,
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

    func test_dialogSignOut_withAffectedRepos() {
        let account = GitHubAccount(id: accountId, login: "carlos-li", host: "github.com")
        let repos = [
            makeRepo(name: "aerie", owner: "carlos-li", repo: "aerie"),
            makeRepo(name: "bridge", owner: "carlos-li", repo: "bridge"),
            makeRepo(name: "orbital", owner: "carlos-li", repo: "orbital"),
        ]
        let view = DialogSignOut(account: account, affectedRepos: repos,
                                  onConfirm: { }, onCancel: { })
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }
}
