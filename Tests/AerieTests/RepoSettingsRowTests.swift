import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `RepoSettingsRow` — the standard case (account
/// matches the dropdown) and the orphan case (repo's primaryAccountId
/// doesn't match any provided account, dropdown shows "(no account)").
final class RepoSettingsRowTests: XCTestCase {
    private let accountId = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!
    private let otherId   = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    private func host<V: View>(_ view: V) -> NSHostingView<some View> {
        let wrapped = ZStack {
            Backdrop()
            view
        }
        .frame(width: 820, height: 80)
        return NSHostingView(rootView: wrapped)
    }

    func test_repoSettingsRow_withAccount() {
        let account = GitHubAccount(id: accountId, login: "carlos-li", host: "github.com")
        let repo = Repository(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!,
            name: "Aerie",
            localPath: URL(fileURLWithPath: "/opt/repos/aerie"),
            githubOwner: "carlos-li",
            githubRepo: "aerie",
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: 0,
            hidden: false
        )
        let view = RepoSettingsRow(
            repo: repo,
            accounts: [account],
            onChangeAccount: { _ in },
            onRemove: { }
        )
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 820, height: 80)))
    }

    func test_repoSettingsRow_noMatchingAccount() {
        let account = GitHubAccount(id: otherId, login: "cli-work", host: "github.com")
        let repo = Repository(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000002")!,
            name: "Bridge",
            localPath: URL(fileURLWithPath: "/opt/repos/bridge"),
            githubOwner: "carlos-li",
            githubRepo: "bridge",
            defaultBranch: "develop",
            primaryAccountId: accountId,  // not in `accounts` below
            sortOrder: 0,
            hidden: false
        )
        let view = RepoSettingsRow(
            repo: repo,
            accounts: [account],
            onChangeAccount: { _ in },
            onRemove: { }
        )
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 820, height: 80)))
    }
}
