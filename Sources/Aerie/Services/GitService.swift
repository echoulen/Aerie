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

        // Ahead/behind against origin/<defaultBranch>. We use subprocess git
        // because SwiftGitX 0.4.0 does not expose `git_graph_ahead_behind`
        // and the `pointer` is module-internal. Subprocess git is fast,
        // reliable, and matches what the user would see in their terminal.
        //
        // For Task 5.2, the caller of readStatus doesn't yet know the default
        // branch (proper detection lands in Task 5.3). We use `main` as a
        // best-effort fallback here; if `origin/main` doesn't exist we'll
        // just get zeros, which is the desired graceful-degradation behaviour.
        let defaultBranch = "main"

        let (ahead, behind) = aheadBehind(
            at: url,
            defaultBranch: defaultBranch,
            currentBranch: currentBranch
        )
        let unpushed = unpushedCommitCount(at: url)

        return LocalGitStatus(
            repoId: repoId,
            currentBranch: currentBranch,
            isDirty: isDirty,
            dirtyFileCount: dirtyFileCount,
            aheadOfDefault: ahead,
            behindOfDefault: behind,
            unpushedCommits: unpushed,
            // TODO(Task 5.3): resolve `refs/remotes/origin/HEAD` and read the
            // tip SHA of the default branch.
            originDefaultSha: "",
            fetchedAt: Date()
        )
    }

    // MARK: - Subprocess helpers

    /// Run `git` with the given arguments against `cwd`. Returns trimmed
    /// stdout on success, nil on any error (missing ref, no remote, etc.).
    /// This is intentionally lossy: most callers in this file treat absence
    /// as "zero" rather than propagating the error.
    private func runGit(_ args: [String], at cwd: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", cwd.path] + args
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Count commits between `origin/<defaultBranch>` and the current branch.
    /// Returns `(ahead, behind)`. Defaults to `(0, 0)` if either ref is
    /// missing — e.g. a local-only repo with no `origin` remote.
    private func aheadBehind(
        at url: URL,
        defaultBranch: String,
        currentBranch: String
    ) -> (ahead: Int, behind: Int) {
        guard !currentBranch.isEmpty else { return (0, 0) }
        // `--left-right --count <left>...<right>` prints "<left>\t<right>".
        // Left = behind (commits in origin/<defaultBranch> missing from HEAD),
        // Right = ahead (commits in HEAD missing from origin/<defaultBranch>).
        let spec = "origin/\(defaultBranch)...\(currentBranch)"
        guard let raw = runGit(
            ["rev-list", "--left-right", "--count", spec],
            at: url
        ) else { return (0, 0) }
        let parts = raw.split(whereSeparator: { $0.isWhitespace })
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1])
        else { return (0, 0) }
        return (ahead, behind)
    }

    /// Count of commits on `HEAD` that aren't yet pushed to its upstream.
    /// Returns `0` when there is no upstream (the common local-only case).
    private func unpushedCommitCount(at url: URL) -> Int {
        guard let raw = runGit(
            ["rev-list", "--count", "@{upstream}..HEAD"],
            at: url
        ) else { return 0 }
        return Int(raw) ?? 0
    }
}
