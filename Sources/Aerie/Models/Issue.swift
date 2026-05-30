import Foundation

/// A single label attached to a GitHub issue. Carries GitHub's own `color`
/// (a 6-digit hex string with no leading `#`, e.g. `"d73a4a"`) so the UI can
/// tint each pill with the repo's real label colour rather than collapsing
/// everything into a fixed palette.
struct IssueLabel: Codable, Equatable {
    let name: String
    let color: String
}

/// An open GitHub issue, mirrored locally for the Issues tab.
///
/// Deliberately parallel to ``PullRequest`` so the Issues pipeline (fetch →
/// cache → project) reuses the same shape the PRs pipeline already established.
/// `assignedToMe` is the issue-side analogue of `PullRequest.isMine`, but —
/// unlike PRs — it is computed for real (the GraphQL query compares each
/// issue's assignees against the fetching token's `viewer.login`), so the
/// header's "N assigned to you" count is meaningful.
struct Issue: Codable, Equatable, Identifiable {
    let id: UUID
    let repoId: UUID
    let number: Int
    let title: String
    let authorLogin: String
    let assignedToMe: Bool
    let labels: [IssueLabel]
    let commentCount: Int
    let htmlUrl: URL
    let updatedAt: Date
}
