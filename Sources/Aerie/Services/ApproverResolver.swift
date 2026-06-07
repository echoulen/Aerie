import Foundation

/// Which accounts may approve a given PR, and the preferred default. GitHub
/// forbids approving your own PR, so the author's account is never eligible.
struct ApproverResolution: Equatable {
    /// Accounts whose login differs from the PR author — i.e. allowed to approve.
    let eligible: [GitHubAccount]
    /// The account to approve as by default: the repo's bound account when it's
    /// eligible (it can always see the repo), otherwise the first other eligible
    /// account. `nil` when nobody can approve (only the author is configured).
    let defaultApprover: GitHubAccount?

    var canApprove: Bool { defaultApprover != nil }
    /// True when more than one account could approve, so the dialog should offer
    /// a picker rather than silently choosing.
    var needsPicker: Bool { eligible.count > 1 }
}

/// Pure resolution of the approver set. Login-based only (no network): the
/// bound account is known-visible, and a non-bound pick that can't see the repo
/// surfaces a clear error at approve time rather than being filtered here.
enum ApproverResolver {
    static func resolve(
        accounts: [GitHubAccount],
        boundAccountId: UUID,
        authorLogin: String
    ) -> ApproverResolution {
        let author = authorLogin.lowercased()
        let eligible = accounts.filter { $0.login.lowercased() != author }

        let bound = accounts.first { $0.id == boundAccountId }
        let preferred: GitHubAccount?
        if let bound, bound.login.lowercased() != author {
            preferred = bound
        } else {
            preferred = eligible.first
        }
        return ApproverResolution(eligible: eligible, defaultApprover: preferred)
    }
}
