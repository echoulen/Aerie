import Foundation

/// Persists the `login` of the account the last approval was submitted as, per
/// repo AND per repo + PR author — so the approver picker (manual
/// `DialogApprove`) and the AI Review default both remember the user's choice
/// across launches.
///
/// The author-scoped memory matters when the author is also the repo's usual
/// approver (your own PR in a repo bound to you): the repo-wide pick is then
/// ineligible, and without a per-author pick the default would fall through to
/// whichever account happens to be listed first.
///
/// Backed by the shared `settings` key-value table; no schema migration. The
/// login (not the account UUID) is stored: a removed-then-re-added account gets
/// a fresh UUID, but its login is stable, so the memory survives account churn.
///
/// Failures are swallowed — remembering an approver is a convenience, never a
/// reason to fail an approve flow.
struct LastApproverStore: Sendable {
    let settings: SettingsDAO

    private func repoKey(_ repoId: UUID) -> String {
        "review.last_approver.\(repoId.uuidString)"
    }

    private func authorKey(_ repoId: UUID, _ author: String) -> String {
        "review.last_approver.\(repoId.uuidString).author.\(author.lowercased())"
    }

    func record(_ login: String, forRepo repoId: UUID, author: String) async {
        try? await settings.setString(authorKey(repoId, author), login)
        try? await settings.setString(repoKey(repoId), login)
    }

    /// Remembered logins in preference order: this repo + author, then this
    /// repo. Feed to `ApproverResolver.resolve(preferredLogins:)`.
    func logins(forRepo repoId: UUID, author: String) async -> [String] {
        [
            try? await settings.getString(authorKey(repoId, author)),
            try? await settings.getString(repoKey(repoId)),
        ].compactMap { $0 }
    }
}
