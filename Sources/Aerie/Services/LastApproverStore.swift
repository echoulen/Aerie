import Foundation

/// Persists, per repo, the `login` of the account the last approval was
/// submitted as — so the approver picker (manual `DialogApprove`) and the AI
/// Review default both remember the user's choice across launches.
///
/// Backed by the shared `settings` key-value table; no schema migration. The
/// login (not the account UUID) is stored: a removed-then-re-added account gets
/// a fresh UUID, but its login is stable, so the memory survives account churn.
///
/// Failures are swallowed — remembering an approver is a convenience, never a
/// reason to fail an approve flow.
struct LastApproverStore: Sendable {
    let settings: SettingsDAO

    private func key(_ repoId: UUID) -> String {
        "review.last_approver.\(repoId.uuidString)"
    }

    func record(_ login: String, forRepo repoId: UUID) async {
        try? await settings.setString(key(repoId), login)
    }

    func login(forRepo repoId: UUID) async -> String? {
        try? await settings.getString(key(repoId))
    }
}
