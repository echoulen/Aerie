import Observation

/// Owns background execution + state for the repo/worktree-scoped row actions
/// (Hard-reset, Discard-unstaged, Discard-worktree, Delete-worktree, and the
/// worktree "Merge from origin" button). Structurally identical to
/// `PRActionStore` — see that type's doc comment — except a kind's target can
/// be either the repo itself or one of its worktrees, so the key needs both.
@MainActor
@Observable
final class RepoActionStore {
    enum Kind: String { case hardReset, discardUnstaged, discardWorktree, deleteWorktree, mergeWorktree }

    /// `.repo` kinds (`hardReset`/`discardUnstaged`) key off the repo;
    /// `.worktree` kinds (`discardWorktree`/`deleteWorktree`/`mergeWorktree`)
    /// key off the worktree path. Callers pass whichever case matches the
    /// kind they're driving — mismatches are a caller bug, not something this
    /// store defends against.
    enum Target {
        case repo(Repository)
        case worktree(WorktreeRow)
    }

    private(set) var phases: [String: ActionPhase] = [:]
    private var running: Set<String> = []
    private var retryWork: [String: () async -> String?] = [:]

    private static func key(_ target: Target, _ kind: Kind) -> String {
        switch target {
        case .repo(let repo):    return "\(repo.id.uuidString)#\(kind.rawValue)"
        case .worktree(let wt):  return "\(wt.path.path)#\(kind.rawValue)"
        }
    }

    func phase(_ kind: Kind, for target: Target) -> ActionPhase {
        phases[Self.key(target, kind)] ?? .idle
    }

    func isRunning(_ kind: Kind, for target: Target) -> Bool {
        if case .running = phase(kind, for: target) { return true }
        return false
    }

    func start(_ kind: Kind, target: Target, work: @escaping () async -> String?) {
        let key = Self.key(target, kind)
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

    func retry(_ kind: Kind, target: Target) {
        let key = Self.key(target, kind)
        guard let work = retryWork[key] else { return }
        start(kind, target: target, work: work)
    }

    func dismiss(_ kind: Kind, target: Target) {
        phases[Self.key(target, kind)] = .idle
    }
}
