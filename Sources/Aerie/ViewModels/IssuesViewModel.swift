import Foundation
import Observation

/// A single issue row displayed by the Issues view — a flattened pair of the
/// issue and its owning repository.
struct IssueRow: Equatable, Identifiable {
    var id: UUID { issue.id }
    let issue: Issue
    let repo: Repository
}

/// State machine for the Issues view.
enum IssuesState: Equatable {
    case loading
    case ready([IssueRow])
    case empty
    case error(String)
}

/// View model for the Issues tab.
///
/// Reads from the local caches only — fetching from GitHub is the polling
/// layer's job (`IssueSyncService`, driven by `PollingScheduler`). `refresh()`
/// re-projects whatever's currently in the cache into a flat, `updatedAt`-sorted
/// row list, and is re-invoked whenever a sync posts `.aerieIssueCacheDidChange`.
/// Mirrors ``PRsViewModel``.
@Observable
final class IssuesViewModel {
    private(set) var state: IssuesState = .loading
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// Re-reads repos + cached issues from the database and projects them into
    /// `state`. Excludes hidden repos.
    func refresh() async {
        do {
            let repos = try await db.repos.all().filter { !$0.hidden }
            if repos.isEmpty {
                state = .empty
                return
            }
            var rows: [IssueRow] = []
            for repo in repos {
                let issues = try await db.issueCache.issues(forRepo: repo.id)
                for issue in issues {
                    rows.append(IssueRow(issue: issue, repo: repo))
                }
            }
            rows.sort { $0.issue.updatedAt > $1.issue.updatedAt }
            state = rows.isEmpty ? .empty : .ready(rows)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
