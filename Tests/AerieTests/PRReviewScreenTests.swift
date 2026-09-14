import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the review screen's adaptive layouts — in particular
/// that a long branch name no longer pushes the header (and the diff with it)
/// wider than a narrow window.
@MainActor
final class PRReviewScreenTests: XCTestCase {
    private func row() -> PRRow {
        let repo = Repository(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            name: "aerie", localPath: URL(fileURLWithPath: "/tmp/aerie"),
            githubOwner: "echoulen", githubRepo: "aerie", defaultBranch: "main",
            primaryAccountId: UUID(uuidString: "30000000-0000-0000-0000-0000000000aa")!,
            sortOrder: 0, hidden: false)
        var pr = PullRequest(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            repoId: repo.id, number: 105,
            title: "fix(updates): only offer an update once its installer zip is uploaded",
            authorLogin: "echoulen", sourceBranch: "fix/update-wait-for-asset-with-a-very-long-branch-name",
            isMine: true, state: .open, ciState: .success, reviewState: .reviewRequired, labels: [],
            htmlUrl: URL(string: "https://github.com/echoulen/aerie/pull/105")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        pr.additions = 100
        pr.deletions = 35
        pr.changedFiles = 2
        return PRRow(pr: pr, repo: repo, localState: nil)
    }

    private let files = [
        PRFileChange(
            filename: "Sources/Aerie/Services/UpdateChecker.swift",
            status: .modified, additions: 3, deletions: 1,
            patch: """
            @@ -40,4 +40,6 @@ protocol ReleaseFetching: Sendable {
             /// stub instead of hitting the network.
            -    func latestRelease() async throws -> (tag: String, url: URL)
            +    func latestRelease() async throws -> ReleaseInfo
            +    // A deliberately long line to check that code wraps instead of widening the screen in narrow windows
            +    var url = URL(string: "https://api.github.com/repos/echoulen/Aerie/releases/latest")!
             }
            """),
    ]

    private func assertReviewSnapshot(width: CGFloat, widthClass: WidthClass,
                                      testName: String = #function) async throws {
        let files = self.files
        let store = AIReviewStore(
            loadFiles: { _ in files },
            runReview: { _, _, _ in .failed("unused") },
            resolveApprover: { _ in ApproverResolution(eligible: [], defaultApprover: nil) },
            approve: { _, _, _ in nil },
            requestChanges: { _, _, _ in nil })
        let view = ZStack {
            Backdrop()
            PRReviewScreen(
                row: row(), store: store, actionStore: PRActionStore(),
                loadFiles: { _ in files }, accountsProvider: { [] })
        }
        .environment(\.widthClass, widthClass)
        .frame(width: width, height: 760)

        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: width, height: 760)
        host.layoutSubtreeIfNeeded()
        // Let the screen's `.task` load the (stubbed) diff before capturing.
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 20_000_000)
            host.layoutSubtreeIfNeeded()
        }
        assertSnapshot(of: host, as: .image(size: CGSize(width: width, height: 760)), testName: testName)
    }

    func test_reviewScreen_medium_longBranchStaysInsideWindow() async throws {
        try await assertReviewSnapshot(width: 700, widthClass: .medium)
    }

    func test_reviewScreen_compact_bottomActionBar() async throws {
        try await assertReviewSnapshot(width: 520, widthClass: .compact)
    }
}
