import SwiftUI
import Observation

/// PR-publish lifecycle for one repo. `.running` carries accumulated progress
/// lines; `.done` carries the created PR's number + URL for the footer pill.
/// `.nothingToDo` is transient — the store reverts it to `.idle` after a few
/// seconds so the card returns to rest without user action.
enum PRCreatePhase: Equatable {
    case idle
    case running([String])
    case done(prNumber: Int, url: URL)
    case failed(String)
    case nothingToDo
}

/// Owns PR-publish execution + state for ALL repos, keyed by the repo's
/// persisted id (stable across refreshes — unlike PR rows, no composite key
/// needed). Held by `MainShell`, not the per-screen VM, so a run survives tab
/// switches and Repos list rebuilds. In-memory only: quit kills the child
/// process and the phase, same tradeoff as `AIReviewStore`.
@MainActor
@Observable
final class PRCreateStore {
    private(set) var phases: [UUID: PRCreatePhase] = [:]
    private var running: Set<UUID> = []
    /// In-flight nothingToDo → idle revert timers, cancelled when a new run
    /// starts so a stale timer can't truncate a later occurrence's window.
    private var revertTasks: [UUID: Task<Void, Never>] = [:]
    private let maxLines = 200

    private let runCreate: (RepoRow, @escaping @Sendable (String) -> Void) async -> PRCreateOutcome
    private let onCreated: () async -> Void
    private let nothingToDoRevertNanos: UInt64

    init(
        runCreate: @escaping (RepoRow, @escaping @Sendable (String) -> Void) async -> PRCreateOutcome,
        onCreated: @escaping () async -> Void,
        nothingToDoRevertSeconds: TimeInterval = 4
    ) {
        self.runCreate = runCreate
        self.onCreated = onCreated
        self.nothingToDoRevertNanos = UInt64(nothingToDoRevertSeconds * 1_000_000_000)
    }

    func phase(for row: RepoRow) -> PRCreatePhase { phases[row.repo.id] ?? .idle }

    /// Whether a publish is in flight for `row`. The card derives its spinner
    /// state from `phase(for:)` directly; this helper mirrors
    /// `AIReviewStore.isRunning` for callers that only need a Bool.
    func isRunning(for row: RepoRow) -> Bool {
        if case .running = phase(for: row) { return true }
        return false
    }

    /// Starts a publish for `row` (no-op if one is already running for it).
    /// Runs in a Task NOT tied to any view, so tab switches don't cancel it.
    func start(row: RepoRow) {
        let id = row.repo.id
        guard !running.contains(id) else { return }
        running.insert(id)
        revertTasks.removeValue(forKey: id)?.cancel()
        phases[id] = .running([])

        Task {
            defer { self.running.remove(id) }
            let onLine: @Sendable (String) -> Void = { line in
                Task { @MainActor [weak self] in self?.appendLine(line, to: id) }
            }
            switch await self.runCreate(row, onLine) {
            case .created(let n, let url, _):
                self.phases[id] = .done(prNumber: n, url: url)
                await self.onCreated()
            case .nothingToDo:
                self.phases[id] = .nothingToDo
                self.scheduleNothingToDoRevert(id)
            case .failed(let m):
                self.phases[id] = .failed(m)
            }
        }
    }

    private func scheduleNothingToDoRevert(_ id: UUID) {
        revertTasks.removeValue(forKey: id)?.cancel()
        revertTasks[id] = Task { [weak self, nothingToDoRevertNanos] in
            try? await Task.sleep(nanoseconds: nothingToDoRevertNanos)
            guard !Task.isCancelled, let self,
                  case .nothingToDo = self.phases[id] else { return }
            self.phases[id] = .idle
        }
    }

    private func appendLine(_ line: String, to id: UUID) {
        guard case .running(var lines) = (phases[id] ?? .idle) else { return }
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        phases[id] = .running(lines)
    }
}
