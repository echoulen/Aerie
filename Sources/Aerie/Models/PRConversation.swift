import Foundation

/// What was said and pushed on a PR: reviews, conversation comments, inline
/// review-thread comments, and commits. Fetched on demand when AI Review
/// re-runs, so it can follow up on its previous review instead of starting
/// blind.
struct PRConversation: Equatable, Sendable {
    struct Review: Equatable, Sendable {
        let author: String
        /// GitHub's review state: APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED.
        let state: String
        let body: String
        let submittedAt: Date
        /// Head commit the review was left on; nil when GitHub no longer has it.
        let commitOid: String?
    }

    struct Comment: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// A comment in the PR's conversation tab.
            case conversation
            /// A comment in a review thread on a line of the diff.
            case inline(path: String, line: Int?)
            /// The body of someone's (non-AI) review.
            case review(state: String)
        }
        let author: String
        let body: String
        let createdAt: Date
        let kind: Kind
    }

    struct Commit: Equatable, Sendable {
        let oid: String
        let headline: String
    }

    /// Oldest first.
    let reviews: [Review]
    /// Conversation and inline comments, in no particular order.
    let comments: [Comment]
    /// Oldest first.
    let commits: [Commit]
}

/// Recognises the reviews Aerie's AI Review posts.
enum AIReviewMarker {
    /// Invisible on GitHub (an HTML comment), leads every AI review body.
    static let tag = "<!-- aerie:ai-review -->"
    /// The footer AI reviews carried before the tag existed. Reviews already
    /// posted that way still have to be found.
    static let legacyFooter = "*Reviewed by Claude Code*"

    static func isAIReview(_ body: String) -> Bool {
        body.contains(tag) || body.contains(legacyFooter)
    }
}

/// Everything since Aerie's most recent AI review on a PR: the replies to it
/// and the commits pushed after it.
struct AIReviewFollowUp: Equatable, Sendable {
    let previous: PRConversation.Review
    /// Replies from anyone after `previous`, oldest first. AI review bodies and
    /// the empty review shells GitHub creates for inline replies are left out.
    let responses: [PRConversation.Comment]
    /// Commits after the one `previous` was left on, oldest first.
    let newCommits: [PRConversation.Commit]
    /// The reviewed commit is no longer in the PR (force-push / rebase), so
    /// which commits are new can't be told.
    let historyRewritten: Bool

    var hasActivity: Bool { !responses.isEmpty || !newCommits.isEmpty || historyRewritten }

    /// Nil when Aerie never AI-reviewed this PR.
    static func from(_ conversation: PRConversation) -> AIReviewFollowUp? {
        guard let previous = conversation.reviews.last(where: { AIReviewMarker.isAIReview($0.body) })
        else { return nil }
        let since = previous.submittedAt

        let comments = conversation.comments.filter {
            $0.createdAt > since && !AIReviewMarker.isAIReview($0.body)
        }
        let reviews = conversation.reviews
            .filter {
                $0.submittedAt > since
                    && !AIReviewMarker.isAIReview($0.body)
                    && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map { PRConversation.Comment(author: $0.author, body: $0.body, createdAt: $0.submittedAt,
                                          kind: .review(state: $0.state)) }
        let responses = (comments + reviews).sorted { $0.createdAt < $1.createdAt }

        let reviewedIndex = previous.commitOid.flatMap { oid in
            conversation.commits.firstIndex { $0.oid == oid }
        }
        return AIReviewFollowUp(
            previous: previous,
            responses: responses,
            newCommits: reviewedIndex.map { Array(conversation.commits[($0 + 1)...]) } ?? [],
            historyRewritten: reviewedIndex == nil
        )
    }
}

/// Whether anyone answered a PR's latest changes request — the PR list's
/// "responded, awaiting re-review" signal. Computed from a few cheap fields on
/// the polling query, so it can't read review bodies: it applies to any
/// changes request, AI or human.
enum ChangesRequestResponse {
    struct Activity: Equatable, Sendable {
        let author: String
        let at: Date
    }

    static func responded(
        reviewer: String, reviewedAt: Date, reviewedCommit: String?, headCommit: String?,
        activity: [Activity]
    ) -> Bool {
        // New commits (or the reviewed one is gone) count as a response.
        if let headCommit, headCommit != reviewedCommit { return true }
        let reviewer = reviewer.lowercased()
        return activity.contains { $0.at > reviewedAt && $0.author.lowercased() != reviewer }
    }
}
