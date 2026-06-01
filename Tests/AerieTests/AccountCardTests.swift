import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `AccountCard` across the three visual permutations
/// the design has to handle (primary + recent call + multi-repo, secondary
/// + no calls + zero repos, and the singular "1 repo" form).
///
/// Both `now` and `lastUsed` are fixed `Date(timeIntervalSince1970:)` values
/// so the relative-time string stays stable across runs.
final class AccountCardTests: XCTestCase {
    // MARK: - Fixtures

    /// Reference "now" — 5 minutes after the lastUsed below.
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_300)
    private let lastUsedRecent = Date(timeIntervalSince1970: 1_700_000_000)

    private let primaryId   = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let secondaryId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!

    private func host(_ row: AccountRow) -> NSHostingView<some View> {
        let view = ZStack {
            Backdrop()
            AccountCard(row: row, now: fixedNow)
                .padding(20)
        }
        .frame(width: 760, height: 180)
        return NSHostingView(rootView: view)
    }

    // MARK: - Tests

    func test_accountCard_primaryWithRecentCall() {
        let row = AccountRow(
            account: GitHubAccount(id: primaryId, login: "carlos-li", host: "github.com"),
            scopes: ["repo", "read:org"],
            isPrimary: true,
            repoCount: 12,
            lastUsed: lastUsedRecent
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 760, height: 180)))
    }

    func test_accountCard_secondaryNoRecentCall() {
        let row = AccountRow(
            account: GitHubAccount(id: secondaryId, login: "cli-work", host: "github.com"),
            scopes: ["repo"],
            isPrimary: false,
            repoCount: 0,
            lastUsed: nil
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 760, height: 180)))
    }

    func test_accountCard_singleRepo() {
        let row = AccountRow(
            account: GitHubAccount(id: secondaryId, login: "c-internal", host: "ghe.orbital.dev"),
            scopes: ["repo", "read:org", "workflow"],
            isPrimary: false,
            repoCount: 1,
            lastUsed: lastUsedRecent
        )
        assertSnapshot(of: host(row), as: .image(size: CGSize(width: 760, height: 180)))
    }
}
