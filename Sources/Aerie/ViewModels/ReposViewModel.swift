import Foundation
import Observation

/// A single repo row displayed by the Repos view — a flattened pair of the
/// `Repository` and (if available) the cached local git status for it, plus
/// the live worktrees attached to the repo.
struct RepoRow: Equatable, Identifiable {
    var id: UUID { repo.id }
    let repo: Repository
    let status: LocalGitStatus?
    var worktrees: [WorktreeRow] = []
    /// The checked-out off-default branch's merged-PR info, when detected. Drives
    /// the `merged · #N` pill and the "Reset & delete branch" affordance.
    var mergedBranch: MergedBranchInfo? = nil
}

/// State machine for the Repos view.
enum ReposState: Equatable {
    case loading
    case ready([RepoRow])
    case empty
    case error(String)
}

/// View model for the Repos tab.
///
/// Reads from the local caches only — fetching git status is the polling
/// layer's job. `refresh()` projects the current repo set (excluding hidden)
/// plus their cached `LocalGitStatus` into `state`, then computes live
/// worktrees and updates `state` again if anything changed.
///
/// `RepoDAO.all()` already orders by `(sort_order, name)` — we preserve that
/// ordering rather than re-sorting in memory.
@MainActor
@Observable
final class ReposViewModel {
    private(set) var state: ReposState = .loading
    /// A repo-action failure (currently: delete). Rendered by `ReposScreen`
    /// under the header; cleared by the next successful action.
    private(set) var actionError: String?
    private let db: AppDatabase
    private let gitService: any GitService
    /// Last-known worktrees per repo, kept in memory so a refresh paints the
    /// rail instantly from the previous read, then updates after the live
    /// recompute. Never persisted (the spec's "live, no DB" strategy).
    private var worktreesByRepo: [UUID: [WorktreeRow]] = [:]

    init(db: AppDatabase, gitService: any GitService) {
        self.db = db
        self.gitService = gitService
    }

    /// Re-reads repos + cached git status from the database and projects
    /// them into `state`. Excludes hidden repos. Then computes live worktrees
    /// and re-projects if anything changed.
    func refresh() async {
        do {
            let all = try await db.repos.all().filter { !$0.hidden }
            if all.isEmpty {
                state = .empty
                return
            }

            // Stage 1 — project repos + cached status immediately, filling the
            // rail from the in-memory worktree cache (empty on first run).
            var rows: [RepoRow] = []
            for repo in all {
                let status = try await db.gitStatusCache.status(forRepo: repo.id)
                let merged = try await db.mergedBranchCache.info(forRepo: repo.id)
                rows.append(RepoRow(
                    repo: repo, status: status,
                    worktrees: worktreesByRepo[repo.id] ?? [],
                    mergedBranch: merged))
            }
            state = .ready(rows)

            // Stage 2 — recompute worktrees live and re-project if anything moved.
            var changed = false
            for (i, repo) in all.enumerated() {
                let wts = await gitService.worktrees(mainWorktreeAt: repo.localPath)
                if worktreesByRepo[repo.id] != wts {
                    worktreesByRepo[repo.id] = wts
                    changed = true
                }
                rows[i] = RepoRow(
                    repo: repo, status: rows[i].status, worktrees: wts,
                    mergedBranch: rows[i].mergedBranch)
            }
            if changed { state = .ready(rows) }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Optimistic, synchronous reorder for the Repos tab's drag-and-drop:
    /// settles the in-memory visible order in the SAME frame the user releases
    /// the card, then persists in the background. `to` uses SwiftUI's
    /// `move(fromOffsets:toOffset:)` semantics (insert-before index in the
    /// pre-removal space) — the same contract as the Settings reorder.
    func applyReorder(from: Int, to: Int) {
        guard case .ready(var rows) = state,
              from != to, to != from + 1,
              rows.indices.contains(from), (0...rows.count).contains(to) else { return }
        let moved = rows.remove(at: from)
        rows.insert(moved, at: to > from ? to - 1 : to)
        state = .ready(rows)
        let orderedIds = rows.map(\.repo.id)
        Task { await persistVisibleOrder(orderedIds) }
    }

    /// Rewrites `sort_order` so the visible repos take `orderedIds`' order
    /// while hidden repos keep their original slots: walk the full old order,
    /// keep hidden entries in place, refill visible slots from the new order,
    /// then write sequential indices. Sequential (not value-recycling) so
    /// duplicate legacy sort_order values can't make the result ambiguous.
    private func persistVisibleOrder(_ orderedIds: [UUID]) async {
        guard let all = try? await db.repos.all(),
              all.filter({ !$0.hidden }).count == orderedIds.count else { return }
        var nextVisible = orderedIds.makeIterator()
        let merged: [UUID] = all.map { $0.hidden ? $0.id : (nextVisible.next() ?? $0.id) }
        for (i, id) in merged.enumerated() {
            try? await db.repos.setSortOrder(id: id, i)
        }
    }

    /// Untracks the repo (DB row + child caches; the on-disk clone is
    /// untouched), refreshes, and notifies Settings via
    /// `.aerieReposDidChange`. Failures land in `actionError` instead of
    /// vanishing — a swallowed FK failure once made the Settings × look dead.
    func remove(id: UUID) async {
        do {
            try await db.repos.delete(id: id)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
            return
        }
        await refresh()
        NotificationCenter.default.post(name: .aerieReposDidChange, object: nil)
    }
}
