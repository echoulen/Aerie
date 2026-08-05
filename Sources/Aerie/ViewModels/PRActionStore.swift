import Observation

/// Lifecycle of one background row action (Merge, Approve, Force-checkout,
/// Hard-reset, Discard, …). Mirrors `AIReviewPhase` but has no intermediate
/// progress payload — these actions don't stream.
enum ActionPhase: Equatable {
    case idle
    case running
    case failed(String)
}

/// Owns background execution + state for the 3 PR-scoped row actions (Merge,
/// Approve, Force-checkout), keyed by a STABLE per-PR-per-kind key (repo id +
/// PR number + kind), so a run survives the PR list re-fetching (which mints a
/// fresh `PullRequest.id` every time — see `AIReviewStore`). Held by
/// `MainShell`, not any per-screen view model, and its `Task`s are never tied
/// to a view, so navigating away doesn't cancel an in-flight action.
@MainActor
@Observable
final class PRActionStore {
    enum Kind: String { case merge, approve, checkout }

    private(set) var phases: [String: ActionPhase] = [:]
    private var running: Set<String> = []
    private var retryWork: [String: () async -> String?] = [:]

    private static func key(_ row: PRRow, _ kind: Kind) -> String {
        "\(row.repo.id.uuidString)#\(row.pr.number)#\(kind.rawValue)"
    }

    func phase(_ kind: Kind, for row: PRRow) -> ActionPhase {
        phases[Self.key(row, kind)] ?? .idle
    }

    func isRunning(_ kind: Kind, for row: PRRow) -> Bool {
        if case .running = phase(kind, for: row) { return true }
        return false
    }

    /// Starts `kind` for `row` (no-op if one's already running for the same
    /// key). `work` returns an error message on failure or `nil` on success —
    /// same contract the modal dialogs' `onConfirm` already used.
    func start(_ kind: Kind, row: PRRow, work: @escaping () async -> String?) {
        let key = Self.key(row, kind)
        guard !running.contains(key) else { return }
        running.insert(key)
        phases[key] = .running
        retryWork[key] = work
        Task {
            defer { self.running.remove(key) }
            let err = await work()
            self.phases[key] = err.map { .failed($0) } ?? .idle
        }
    }

    /// Re-runs the last `work` passed to `start` for this key, without asking
    /// for confirmation again — matches how the old modal dialogs behaved on
    /// a failed attempt (same dialog, same primary button, no re-prompt).
    func retry(_ kind: Kind, row: PRRow) {
        let key = Self.key(row, kind)
        guard let work = retryWork[key] else { return }
        start(kind, row: row, work: work)
    }

    /// Clears a failed phase back to idle (the error strip's Dismiss control).
    func dismiss(_ kind: Kind, row: PRRow) {
        phases[Self.key(row, kind)] = .idle
    }
}
