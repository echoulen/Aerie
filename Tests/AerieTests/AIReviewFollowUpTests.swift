import XCTest
@testable import Aerie

/// A re-run of AI Review must see what happened since its previous review —
/// the author's replies (a fix, or a reason not to fix) and new commits —
/// otherwise it re-raises issues the author already answered.
final class AIReviewFollowUpTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private let aiBody = "<!-- aerie:ai-review -->\n## ⚠️ AI Review · 發現需處理的問題\n- null deref"
    private let legacyAIBody = "## ⚠️ AI Review · 發現需處理的問題\n\n- race\n\n---\n*Reviewed by Claude Code*"

    private func review(_ author: String, _ state: String, _ body: String, _ minutes: Double, commit: String? = "c2") -> PRConversation.Review {
        .init(author: author, state: state, body: body, submittedAt: at(minutes), commitOid: commit)
    }
    private func comment(_ author: String, _ body: String, _ minutes: Double, _ kind: PRConversation.Comment.Kind = .conversation) -> PRConversation.Comment {
        .init(author: author, body: body, createdAt: at(minutes), kind: kind)
    }
    private let commits: [PRConversation.Commit] = [
        .init(oid: "c1", headline: "first"), .init(oid: "c2", headline: "second"),
        .init(oid: "c3", headline: "fix null deref"), .init(oid: "c4", headline: "add test"),
    ]

    // MARK: Marker

    func test_marker_recognisesTaggedAndLegacyBodies() {
        XCTAssertTrue(AIReviewMarker.isAIReview(aiBody))
        XCTAssertTrue(AIReviewMarker.isAIReview(legacyAIBody), "reviews posted before the tag existed still count")
        XCTAssertFalse(AIReviewMarker.isAIReview("LGTM, but please rename foo"))
    }

    // MARK: Follow-up extraction

    func test_noPreviousAIReview_isNotAFollowUp() {
        let conv = PRConversation(
            reviews: [review("maja", "CHANGES_REQUESTED", "please fix", 1)],
            comments: [comment("octocat", "done", 2)], commits: commits)
        XCTAssertNil(AIReviewFollowUp.from(conv))
    }

    func test_picksTheLatestAIReview_andOnlyActivityAfterIt() throws {
        let conv = PRConversation(
            reviews: [
                review("reviewer", "CHANGES_REQUESTED", legacyAIBody, 1, commit: "c1"),
                review("reviewer", "CHANGES_REQUESTED", aiBody, 10, commit: "c2"),
                review("maja", "COMMENTED", "agree with the bot", 12),
                review("octocat", "COMMENTED", "", 13),   // an inline reply's empty review shell
            ],
            comments: [
                comment("octocat", "before the latest review", 5),
                comment("octocat", "fixed in c3", 20),
                comment("octocat", "race can't happen: this runs on the main actor", 15,
                        .inline(path: "Sources/A.swift", line: 42)),
                comment("reviewer", aiBody, 11),          // an AI body posted as a comment is not a response
            ],
            commits: commits)

        let f = try XCTUnwrap(AIReviewFollowUp.from(conv))
        XCTAssertEqual(f.previous.submittedAt, at(10), "the most recent AI review, not the legacy one")
        XCTAssertEqual(f.responses.map(\.body), [
            "agree with the bot",
            "race can't happen: this runs on the main actor",
            "fixed in c3",
        ], "after the review only, oldest first, no AI bodies, no empty review shells")
        XCTAssertEqual(f.responses[0].kind, .review(state: "COMMENTED"))
        XCTAssertEqual(f.responses[1].kind, .inline(path: "Sources/A.swift", line: 42))
        XCTAssertEqual(f.newCommits.map(\.oid), ["c3", "c4"])
        XCTAssertFalse(f.historyRewritten)
        XCTAssertTrue(f.hasActivity)
    }

    func test_noActivitySinceTheReview() throws {
        let conv = PRConversation(
            reviews: [review("reviewer", "CHANGES_REQUESTED", aiBody, 10, commit: "c4")],
            comments: [comment("octocat", "old", 5)], commits: commits)
        let f = try XCTUnwrap(AIReviewFollowUp.from(conv))
        XCTAssertTrue(f.responses.isEmpty)
        XCTAssertTrue(f.newCommits.isEmpty)
        XCTAssertFalse(f.historyRewritten)
        XCTAssertFalse(f.hasActivity)
    }

    func test_reviewedCommitGone_meansHistoryWasRewritten() throws {
        let conv = PRConversation(
            reviews: [review("reviewer", "CHANGES_REQUESTED", aiBody, 10, commit: "old-sha")],
            comments: [], commits: commits)
        let f = try XCTUnwrap(AIReviewFollowUp.from(conv))
        XCTAssertTrue(f.historyRewritten)
        XCTAssertTrue(f.newCommits.isEmpty, "can't tell which commits are new — the prompt says so instead")
        XCTAssertTrue(f.hasActivity)
    }

    // MARK: List signal

    func test_respondedToChangesRequest() {
        typealias R = ChangesRequestResponse
        let reviewedAt = at(10)
        // A new head commit is a response.
        XCTAssertTrue(R.responded(reviewer: "Reviewer", reviewedAt: reviewedAt, reviewedCommit: "c2", headCommit: "c3", activity: []))
        // Same head, someone else spoke afterwards.
        XCTAssertTrue(R.responded(reviewer: "reviewer", reviewedAt: reviewedAt, reviewedCommit: "c2", headCommit: "c2",
                                  activity: [.init(author: "octocat", at: at(11))]))
        // The reviewer talking to themselves isn't a response (login match is case-insensitive).
        XCTAssertFalse(R.responded(reviewer: "Reviewer", reviewedAt: reviewedAt, reviewedCommit: "c2", headCommit: "c2",
                                   activity: [.init(author: "reviewer", at: at(11))]))
        // Activity before the review doesn't count.
        XCTAssertFalse(R.responded(reviewer: "reviewer", reviewedAt: reviewedAt, reviewedCommit: "c2", headCommit: "c2",
                                   activity: [.init(author: "octocat", at: at(9))]))
        // The reviewed commit is unknown (force-pushed away) → treat as new commits.
        XCTAssertTrue(R.responded(reviewer: "reviewer", reviewedAt: reviewedAt, reviewedCommit: nil, headCommit: "c3", activity: []))
    }

    func test_pullRequest_awaitingReReview_onlyWhenChangesRequestedAndResponded() {
        func pr(_ state: ReviewState, _ responded: Bool?) -> PullRequest {
            var p = PullRequest(id: UUID(), repoId: UUID(), number: 1, title: "T", authorLogin: "octocat",
                                sourceBranch: "b", isMine: false, state: .open, ciState: .success,
                                reviewState: state, labels: [], htmlUrl: URL(string: "https://e.com")!,
                                updatedAt: t0)
            p.respondedToChangesRequest = responded
            return p
        }
        XCTAssertTrue(pr(.changesRequested, true).awaitingReReview)
        XCTAssertFalse(pr(.changesRequested, false).awaitingReReview)
        XCTAssertFalse(pr(.changesRequested, nil).awaitingReReview)
        XCTAssertFalse(pr(.approved, true).awaitingReReview, "a stale signal on an approved PR is ignored")
    }
}
