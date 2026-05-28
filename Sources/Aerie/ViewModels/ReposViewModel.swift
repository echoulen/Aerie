import Foundation
import Observation

/// A single repo row displayed by the Repos view — a flattened pair of the
/// `Repository` and (if available) the cached local git status for it.
struct RepoRow: Equatable, Identifiable {
    var id: UUID { repo.id }
    let repo: Repository
    let status: LocalGitStatus?
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
/// plus their cached `LocalGitStatus` into `state`.
///
/// `RepoDAO.all()` already orders by `(sort_order, name)` — we preserve that
/// ordering rather than re-sorting in memory.
@Observable
final class ReposViewModel {
    private(set) var state: ReposState = .loading
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// Re-reads repos + cached git status from the database and projects
    /// them into `state`. Excludes hidden repos.
    func refresh() async {
        do {
            let all = try await db.repos.all().filter { !$0.hidden }
            if all.isEmpty {
                state = .empty
                return
            }
            var rows: [RepoRow] = []
            for repo in all {
                let status = try await db.gitStatusCache.status(forRepo: repo.id)
                rows.append(RepoRow(repo: repo, status: status))
            }
            state = .ready(rows)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
