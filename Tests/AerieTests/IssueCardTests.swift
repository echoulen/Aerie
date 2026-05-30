import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `IssueCard` across the permutations the Issues view
/// has to handle:
///   1. Assigned to you, multiple coloured labels, comments.
///   2. Not assigned, single label, no comments.
///   3. No labels, no comments (bare meta + title).
///
/// Fixed UUIDs + a pinned "now" keep the baselines deterministic.
final class IssueCardTests: XCTestCase {
    private let repoId = UUID(uuidString: "30000000-0000-0000-0000-0000000000a1")!
    private let acctId = UUID(uuidString: "30000000-0000-0000-0000-0000000000b1")!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_010_000)

    private func makeRepo() -> Repository {
        Repository(
            id: repoId,
            name: "aerie",
            localPath: URL(fileURLWithPath: "/opt/repos/aerie"),
            githubOwner: "carlos-li",
            githubRepo: "aerie",
            defaultBranch: "main",
            primaryAccountId: acctId,
            sortOrder: 0,
            hidden: false
        )
    }

    private func makeIssue(
        number: Int,
        title: String,
        assignedToMe: Bool,
        labels: [IssueLabel],
        comments: Int
    ) -> Issue {
        Issue(
            id: UUID(uuidString: "30000000-0000-0000-0000-00000000\(String(format: "%04d", number))")!,
            repoId: repoId,
            number: number,
            title: title,
            authorLogin: "maja-c",
            assignedToMe: assignedToMe,
            assigneeLogins: assignedToMe ? ["maja-c"] : [],
            labels: labels,
            commentCount: comments,
            htmlUrl: URL(string: "https://github.com/carlos-li/aerie/issues/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func host(_ issue: Issue) -> NSHostingView<some View> {
        let row = IssueRow(issue: issue, repo: makeRepo())
        let view = ZStack {
            Backdrop()
            IssueCard(row: row, onOpen: {}, now: fixedNow)
                .padding(20)
        }
        .frame(width: 980, height: 180)
        return NSHostingView(rootView: view)
    }

    func test_issueCard_assignedWithLabelsAndComments() {
        let issue = makeIssue(
            number: 148,
            title: "Polling backs off too aggressively after a 403",
            assignedToMe: true,
            labels: [IssueLabel(name: "bug", color: "d73a4a"), IssueLabel(name: "polling", color: "0e8a16")],
            comments: 6
        )
        assertSnapshot(of: host(issue), as: .image(size: CGSize(width: 980, height: 180)))
    }

    func test_issueCard_unassignedSingleLabel() {
        let issue = makeIssue(
            number: 204,
            title: "Glyph cache leaks under rapid re-render",
            assignedToMe: false,
            labels: [IssueLabel(name: "perf", color: "fbca04")],
            comments: 0
        )
        assertSnapshot(of: host(issue), as: .image(size: CGSize(width: 980, height: 180)))
    }

    /// A label-less card must be exactly as tall as one with labels (the label
    /// row reserves a constant height). Titles are identical 1-liners so the
    /// only variable is label presence.
    func test_issueCard_sameHeight_withAndWithoutLabels() {
        let bare = makeIssue(
            number: 1, title: "Short one-line title",
            assignedToMe: false, labels: [], comments: 0
        )
        let labeled = makeIssue(
            number: 2, title: "Short one-line title",
            assignedToMe: false,
            labels: [IssueLabel(name: "bug", color: "d73a4a")], comments: 3
        )
        XCTAssertEqual(
            cardHeight(bare), cardHeight(labeled), accuracy: 0.5,
            "label presence must not change card height"
        )
    }

    private func cardHeight(_ issue: Issue) -> CGFloat {
        let card = IssueCard(
            row: IssueRow(issue: issue, repo: makeRepo()),
            onOpen: {}, now: fixedNow
        )
        .frame(width: 900)
        let host = NSHostingView(rootView: card)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func test_issueCard_bare() {
        let issue = makeIssue(
            number: 92,
            title: "Document the keychain fallback for headless CI",
            assignedToMe: false,
            labels: [],
            comments: 0
        )
        assertSnapshot(of: host(issue), as: .image(size: CGSize(width: 980, height: 180)))
    }
}
