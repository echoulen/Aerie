import Foundation
import SwiftGitX

/// Service that reads (and later, mutates) state from a local Git repository
/// via SwiftGitX (libgit2).
///
/// `readStatus` is the validation surface for Phase 5 — it must work end-to-end
/// before downstream tasks (5.2 fetch/ahead-behind, 5.3 default-branch detection,
/// 5.4 switch, 5.5 reset) layer on top.
///
/// The signature takes an explicit `repoId` because the git layer is a
/// stateless transformer: the persistence layer is the source of truth for repo
/// identity, so we don't want this service inventing UUIDs.
protocol GitService: Actor {
    func readStatus(at url: URL, repoId: UUID) async throws -> LocalGitStatus
}

actor LiveGitService: GitService {
    init() {}

    func readStatus(at url: URL, repoId: UUID) async throws -> LocalGitStatus {
        // Open the existing repository (do not create one if it doesn't exist).
        // Fully qualify to avoid colliding with our local `Aerie.Repository`
        // domain model.
        let repo = try SwiftGitX.Repository(at: url, createIfNotExists: false)

        // Collect status entries — `.default` already implies
        // `[.includeUntracked, .recurseUntrackedDirectories]`, which matches
        // the user-visible "git status" notion of "dirty".
        let entries = try repo.status(options: SwiftGitX.StatusOption.default)

        // Count anything that isn't strictly `.current` or `.ignored` as
        // contributing to dirtiness. A single file can carry multiple flags
        // (e.g. indexNew + workingTreeModified) — it should still count once.
        let dirtyEntries = entries.filter { entry in
            entry.status.contains { status in
                switch status {
                case .current, .ignored:
                    return false
                default:
                    return true
                }
            }
        }
        let dirtyFileCount = dirtyEntries.count
        let isDirty = dirtyFileCount > 0

        // Resolve the current branch name. HEAD can be:
        //   * a Branch (normal case — `.name` is e.g. "main")
        //   * a Tag (HEAD detached on a tag)
        //   * a Branch with name "HEAD" (detached on a commit)
        // For a fresh repo with an initial commit on `main` the first case fires.
        let currentBranch: String
        do {
            let head = try repo.HEAD
            if let branch = head as? SwiftGitX.Branch, branch.name != "HEAD" {
                currentBranch = branch.name
            } else {
                currentBranch = ""
            }
        } catch {
            // Unborn HEAD (no commits) — leave empty.
            currentBranch = ""
        }

        return LocalGitStatus(
            repoId: repoId,
            currentBranch: currentBranch,
            isDirty: isDirty,
            dirtyFileCount: dirtyFileCount,
            // TODO(Task 5.2): compute ahead/behind/unpushed against origin's
            // default branch after fetch.
            aheadOfDefault: 0,
            behindOfDefault: 0,
            unpushedCommits: 0,
            // TODO(Task 5.3): resolve `refs/remotes/origin/HEAD` and read the
            // tip SHA of the default branch.
            originDefaultSha: "",
            fetchedAt: Date()
        )
    }
}
