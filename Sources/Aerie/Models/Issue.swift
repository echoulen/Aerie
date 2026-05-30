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
///
/// `assigneeLogins` carries every assignee's GitHub login, and `assignedToMe`
/// is the issue-side analogue of `PullRequest.isMine`. Crucially, "me" spans
/// **all connected accounts**, not just the repo's syncing account: a repo is
/// often synced via one account (e.g. a bot) while an issue is assigned to
/// another of the user's logins. `IssueSyncService` resolves `assignedToMe`
/// against the full account set so the "N assigned to you" count is correct.
struct Issue: Codable, Equatable, Identifiable {
    let id: UUID
    let repoId: UUID
    let number: Int
    let title: String
    let authorLogin: String
    let assignedToMe: Bool
    let assigneeLogins: [String]
    let labels: [IssueLabel]
    let commentCount: Int
    let htmlUrl: URL
    let updatedAt: Date

    /// Returns a copy with `assignedToMe` recomputed against `myLogins`
    /// (case-insensitive). Used by `IssueSyncService` once it knows every
    /// connected account's login.
    func resolvingAssignedToMe(myLogins: Set<String>) -> Issue {
        let mine = assigneeLogins.contains { myLogins.contains($0.lowercased()) }
        return Issue(
            id: id, repoId: repoId, number: number, title: title,
            authorLogin: authorLogin, assignedToMe: mine,
            assigneeLogins: assigneeLogins, labels: labels,
            commentCount: commentCount, htmlUrl: htmlUrl, updatedAt: updatedAt
        )
    }
}
