import Foundation
import Observation

/// A single PR row displayed by the PRs view — a flattened triple of the PR,
/// its owning repository, and (if available) the locally-computed branch
/// status for that PR's source branch.
struct PRRow: Equatable, Identifiable {
    var id: UUID { pr.id }
    let pr: PullRequest
    let repo: Repository
    let localState: PRLocalState?
}

/// State machine for the PRs view.
enum PRsState: Equatable {
    case loading
    case ready([PRRow])
    case empty
    case error(String)
}

/// View model for the PRs tab.
///
/// Reads from the local caches only — fetching from GitHub and computing
/// local state is the polling layer's job (Phase 7). `refresh()` re-projects
/// whatever's currently in the cache into a flat, `updatedAt`-sorted row list.
@Observable
final class PRsViewModel {
    private(set) var state: PRsState = .loading
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// Re-reads repos + cached PRs + cached local state from the database and
    /// projects them into `state`. Excludes hidden repos.
    func refresh() async {
        do {
            let repos = try await db.repos.all().filter { !$0.hidden }
            if repos.isEmpty {
                state = .empty
                return
            }
            var rows: [PRRow] = []
            for repo in repos {
                let prs = try await db.prCache.prs(forRepo: repo.id)
                for pr in prs {
                    let local = try await db.prLocalStateCache.state(forPr: pr.id)
                    rows.append(PRRow(pr: pr, repo: repo, localState: local))
                }
            }
            rows.sort { $0.pr.updatedAt > $1.pr.updatedAt }
            state = rows.isEmpty ? .empty : .ready(rows)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
