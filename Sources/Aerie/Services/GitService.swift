import Foundation
import SwiftGitX

/// Summary of work discarded by a `hardResetToOrigin` call. Captures
/// the state of the working tree just before the reset so we can show
/// the user what they lost (or what they would lose, if surfaced in a
/// confirmation dialog).
struct HardResetSummary: Sendable, Equatable {
    let discardedDirtyFiles: Int
    let discardedCommits: Int
}

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

    /// Resolves the local checkout state of a PR's source branch.
    /// Mirrors `readStatus`'s pattern of taking an external identity
    /// (`prId`) so the git layer stays stateless.
    ///
    /// When the branch exists but is not currently checked out, only
    /// existence is reported — dirty/ahead/behind/unpushed are nil because
    /// computing them would require either a worktree switch (destructive)
    /// or a fast-path that doesn't apply to most PR review flows.
    func prLocalState(
        repoAt url: URL, prId: UUID, sourceBranch: String
    ) async throws -> PRLocalState

    /// Destructively reset the working tree to `origin/<defaultBranch>`:
    /// fetches origin, switches to the default branch, then `reset --hard`.
    /// Returns a summary of what was discarded (captured before the reset).
    ///
    /// `token` is the repo's bound account's gh token, used to authenticate the
    /// fetch (see `forceCheckout`). Pass `nil` to fall back to gh's active
    /// account.
    func hardResetToOrigin(
        repoAt url: URL, defaultBranch: String, token: String?
    ) async throws -> HardResetSummary

    /// Bring the repo's current checkout up to date with its base by merging
    /// `origin/<defaultBranch>` into it. Fetches origin first so the merge
    /// target is current. The PR card's "Update branch" pill calls this when the
    /// checked-out branch has fallen behind; afterwards the recomputed `behind`
    /// count is 0 and the pill drops out.
    ///
    /// `token` is the repo's bound account's gh token, used to authenticate the
    /// fetch (see `forceCheckout`). Pass `nil` to fall back to gh's active
    /// account.
    func updateBranchFromBase(
        repoAt url: URL, defaultBranch: String, token: String?
    ) async throws

    /// Discard all UNSTAGED changes in the working tree: `git restore .` drops
    /// unstaged modifications to tracked files, and `git clean -fd` removes
    /// untracked (new) files and directories. Staged changes, commits, and
    /// .gitignore'd paths are kept. Destructive; the repo card gates it behind a
    /// confirmation dialog.
    func discardUnstaged(repoAt url: URL) async throws

    /// Force-checkout the repo onto a PR's origin branch:
    /// `git fetch origin` then `git checkout -f -B <branch> origin/<branch>`.
    /// This resets the local branch to the origin tip, discarding any dirty
    /// working tree and any divergent local commits. Destructive when the local
    /// branch has uncommitted or unpushed work; the PR card gates it behind a
    /// confirmation dialog.
    ///
    /// `token` is the repo's bound account's gh token (`Repository
    /// .primaryAccountId` → `AuthService.token(for:)`). It's exported as
    /// `GH_TOKEN` for the fetch so a private remote authenticates as the
    /// account that can actually see it, not gh's globally-active account. Pass
    /// `nil` to fall back to the active account.
    func forceCheckout(repoAt url: URL, branch: String, token: String?) async throws

    /// List the repo's **extra** git worktrees (the main checkout is filtered
    /// out). Runs `git worktree list --porcelain` against `url` (the main
    /// worktree path) and reads each extra worktree's dirty state via libgit2.
    /// Live, non-persisted, error-tolerant: returns `[]` if git can't be run.
    func worktrees(mainWorktreeAt url: URL) async -> [WorktreeRow]

    /// Remove a worktree: `git worktree remove [--force] <path>`, run from the
    /// main worktree so the checkout deleting itself can't break the command.
    /// `force` deletes even when the worktree has uncommitted changes.
    func removeWorktree(_ worktreePath: URL, mainWorktreeAt mainURL: URL, force: Bool) async throws

    /// Force-delete a local branch: `git branch -D <branch>`. Used after a hard
    /// reset to clean up a branch whose PR has already merged. Force (`-D`)
    /// because a squash-merged branch's commits aren't in the default branch's
    /// history, so a safe `-d` would refuse. The caller must NOT be on `branch`
    /// — `hardResetToOrigin` switches to the default branch first. Throws if git
    /// refuses (e.g. unknown branch).
    func deleteLocalBranch(repoAt url: URL, branch: String) async throws
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

        // Resolve the default branch via origin/HEAD → main → master chain.
        let defaultBranch = detectDefaultBranch(at: url)

        // Ahead/behind against origin/<defaultBranch>. Subprocess git because
        // SwiftGitX 0.4.0 doesn't expose git_graph_ahead_behind and its
        // `Repository.pointer` is module-internal.
        let (ahead, behind) = aheadBehind(
            at: url,
            defaultBranch: defaultBranch,
            currentBranch: currentBranch
        )
        let unpushed = unpushedCommitCount(at: url)
        let originDefaultSha = originDefaultShortSha(
            at: url, defaultBranch: defaultBranch
        )

        return LocalGitStatus(
            repoId: repoId,
            currentBranch: currentBranch,
            isDirty: isDirty,
            dirtyFileCount: dirtyFileCount,
            aheadOfDefault: ahead,
            behindOfDefault: behind,
            unpushedCommits: unpushed,
            originDefaultSha: originDefaultSha,
            fetchedAt: Date()
        )
    }

    // MARK: - PRLocalState

    func prLocalState(
        repoAt url: URL, prId: UUID, sourceBranch: String
    ) async throws -> PRLocalState {
        // 1. Does the local branch exist?
        let exists = runGit(
            ["show-ref", "--verify", "--quiet", "refs/heads/\(sourceBranch)"],
            at: url
        ) != nil

        guard exists else {
            return PRLocalState(
                prId: prId,
                sourceBranch: sourceBranch,
                localBranchExists: false,
                isCurrentBranch: false,
                dirty: nil,
                ahead: nil,
                behind: nil,
                unpushed: nil
            )
        }

        // 2. Is it the current branch?
        let currentBranch = runGit(
            ["symbolic-ref", "--short", "HEAD"], at: url
        ) ?? ""
        let isCurrent = currentBranch == sourceBranch

        guard isCurrent else {
            // Branch exists but not checked out. We report only existence —
            // computing dirty/ahead/behind would require a worktree switch
            // (destructive) or a more expensive tree-diff that we don't need
            // for the PR list rendering today.
            return PRLocalState(
                prId: prId,
                sourceBranch: sourceBranch,
                localBranchExists: true,
                isCurrentBranch: false,
                dirty: nil,
                ahead: nil,
                behind: nil,
                unpushed: nil
            )
        }

        // 3. Current branch — reuse the same machinery as readStatus.
        let repo = try SwiftGitX.Repository(at: url, createIfNotExists: false)
        let entries = try repo.status(options: SwiftGitX.StatusOption.default)
        let dirtyFileCount = entries.filter { entry in
            entry.status.contains { status in
                switch status {
                case .current, .ignored:
                    return false
                default:
                    return true
                }
            }
        }.count
        let isDirty = dirtyFileCount > 0

        let defaultBranch = detectDefaultBranch(at: url)
        let (ahead, behind) = aheadBehind(
            at: url,
            defaultBranch: defaultBranch,
            currentBranch: currentBranch
        )
        let unpushed = unpushedCommitCount(at: url)

        return PRLocalState(
            prId: prId,
            sourceBranch: sourceBranch,
            localBranchExists: true,
            isCurrentBranch: true,
            dirty: isDirty,
            ahead: ahead,
            behind: behind,
            unpushed: unpushed
        )
    }

    // MARK: - Hard reset to origin

    func hardResetToOrigin(
        repoAt url: URL, defaultBranch: String, token: String? = nil
    ) async throws -> HardResetSummary {
        // Capture pre-reset summary BEFORE we mutate anything — once we
        // switch branches and reset --hard, the dirty count and the
        // ahead-of-main count are no longer recoverable.
        let dirtyCount = preResetDirtyFileCount(at: url)

        // Discarded commits = commits on HEAD that aren't reachable from
        // origin/<defaultBranch>. This catches both:
        //   * "on a feature branch with N commits" → N
        //   * "on main but N commits ahead of origin/main" → N
        let currentBranch = runGit(
            ["symbolic-ref", "--short", "HEAD"], at: url
        ) ?? ""
        let (ahead, _) = aheadBehind(
            at: url,
            defaultBranch: defaultBranch,
            currentBranch: currentBranch
        )

        // Fetch origin so origin/<defaultBranch> is up-to-date. Use the git
        // CLI, NOT SwiftGitX/libgit2: libgit2 has no access to the git
        // credential helper / keychain (HTTPS tokens) or ~/.ssh/config host
        // aliases, so its fetch fails to authenticate against a private remote
        // — which surfaced as `SwiftGitXError error 1` on a private HTTPS repo.
        // The CLI authenticates exactly as a manual `git fetch` would — and
        // `token` (the repo's bound account) selects which account, so a private
        // remote the active account can't see still authenticates.
        guard runGit(["fetch", "origin"], at: url, token: token) != nil else {
            throw NSError(
                domain: "GitService", code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't fetch origin — check your network connection and git credentials."]
            )
        }

        // Now the local reset via SwiftGitX (switch + reset --hard need no
        // network, so libgit2's missing credentials don't matter here).
        let repo = try SwiftGitX.Repository(at: url, createIfNotExists: false)

        // Switch to the local default branch (creating it if needed by
        // tracking the remote).
        let defaultLocal: SwiftGitX.Branch
        if let local = repo.branch[defaultBranch, type: .local] {
            defaultLocal = local
            try repo.switch(to: defaultLocal)
        } else {
            // No local default branch yet — `switch` against the remote
            // ref will create one with upstream tracking.
            let remoteBranch = try repo.branch.get(
                named: "origin/\(defaultBranch)", type: .remote
            )
            try repo.switch(to: remoteBranch)
        }

        // Resolve the remote tip and reset --hard.
        let remoteRef = try repo.branch.get(
            named: "origin/\(defaultBranch)", type: .remote
        )
        guard let remoteTip = remoteRef.target as? SwiftGitX.Commit else {
            throw NSError(
                domain: "GitService", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "origin/\(defaultBranch) tip is not a commit"
                ]
            )
        }
        try repo.reset(to: remoteTip, mode: .hard)

        return HardResetSummary(
            discardedDirtyFiles: dirtyCount,
            discardedCommits: ahead
        )
    }

    // MARK: - Discard unstaged

    func discardUnstaged(repoAt url: URL) async throws {
        // Two steps, because "unstaged changes" spans two git notions:
        //   1. `git restore .` reverts working-tree modifications of *tracked*
        //      files back to the index (dropping unstaged edits, keeping staged
        //      changes and commits).
        //   2. `git clean -fd` removes *untracked* files and directories — new
        //      files are unstaged changes too, and the confirmation dialog
        //      counts them in `dirtyFileCount`, so `restore` alone left them
        //      behind. No `-x`, so .gitignore'd paths (build artifacts, .env)
        //      are preserved; staged-new files stay too (they're in the index).
        // Use the git CLI (not libgit2) for parity with the other mutating ops.
        guard runGit(["restore", "."], at: url) != nil else {
            throw NSError(
                domain: "GitService", code: 4,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't discard unstaged changes (git restore . failed)."]
            )
        }
        guard runGit(["clean", "-fd"], at: url) != nil else {
            throw NSError(
                domain: "GitService", code: 5,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't remove untracked files (git clean -fd failed)."]
            )
        }
    }

    // MARK: - Delete local branch

    func deleteLocalBranch(repoAt url: URL, branch: String) async throws {
        // CLI (not libgit2) for parity with the other mutating ops. `-D` force-
        // deletes even when the branch isn't merged into HEAD's upstream — the
        // squash-merge case, where the branch's commits never landed on the
        // default branch under the same SHAs.
        guard runGit(["branch", "-D", branch], at: url) != nil else {
            throw NSError(
                domain: "GitService", code: 9,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't delete local branch \(branch) (git branch -D failed)."]
            )
        }
    }

    // MARK: - Force checkout

    func forceCheckout(repoAt url: URL, branch: String, token: String? = nil) async throws {
        // Fetch via the git CLI (NOT libgit2) for the same credential reason as
        // `hardResetToOrigin`/`updateBranchFromBase`: the CLI uses the keychain /
        // credential helper and ~/.ssh config, so it authenticates against
        // private remotes. `token` picks the repo's bound gh account so the
        // helper doesn't fall back to gh's active (possibly unauthorized) account.
        guard runGit(["fetch", "origin"], at: url, token: token) != nil else {
            throw NSError(
                domain: "GitService", code: 6,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't fetch origin — check your network connection and git credentials."]
            )
        }

        // `checkout -f -B <branch> origin/<branch>`: -f drops the dirty working
        // tree, -B resets (or creates) the local branch to the origin tip. The
        // combination switches to the PR's branch and discards any divergent
        // local commits in one step.
        guard runGit(
            ["checkout", "-f", "-B", branch, "origin/\(branch)"], at: url
        ) != nil else {
            throw NSError(
                domain: "GitService", code: 7,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't check out origin/\(branch) — the branch may not exist on origin."]
            )
        }
    }

    // MARK: - Worktrees

    func worktrees(mainWorktreeAt url: URL) async -> [WorktreeRow] {
        guard let porcelain = runGit(
            ["worktree", "list", "--porcelain"], at: url
        ) else { return [] }

        let parsed = WorktreeParsing.parse(porcelain: porcelain, mainWorktreePath: url)
        return parsed.map { wt in
            let (dirty, count) = wt.prunable ? (false, 0) : worktreeDirtiness(at: wt.path)
            return WorktreeRow(
                path: wt.path,
                branchLabel: wt.branchLabel,
                isDetached: wt.isDetached,
                isDirty: dirty,
                dirtyFileCount: count,
                prunable: wt.prunable
            )
        }
    }

    func removeWorktree(
        _ worktreePath: URL, mainWorktreeAt mainURL: URL, force: Bool
    ) async throws {
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(worktreePath.path)
        guard runGit(args, at: mainURL) != nil else {
            throw NSError(
                domain: "GitService", code: 8,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't remove the worktree — it may have uncommitted changes."]
            )
        }
    }

    /// Dirty file count for a worktree path, mirroring `readStatus`'s notion of
    /// dirty (anything not `.current`/`.ignored`). Returns `(false, 0)` if the
    /// path can't be opened (e.g. it vanished between listing and reading).
    private func worktreeDirtiness(at url: URL) -> (isDirty: Bool, count: Int) {
        do {
            let repo = try SwiftGitX.Repository(at: url, createIfNotExists: false)
            let entries = try repo.status(options: SwiftGitX.StatusOption.default)
            let n = entries.filter { entry in
                entry.status.contains { status in
                    switch status {
                    case .current, .ignored: return false
                    default: return true
                    }
                }
            }.count
            return (n > 0, n)
        } catch {
            return (false, 0)
        }
    }

    // MARK: - Update branch from base

    func updateBranchFromBase(
        repoAt url: URL, defaultBranch: String, token: String? = nil
    ) async throws {
        // Fetch via the git CLI (NOT libgit2) for the same credential reason as
        // `hardResetToOrigin`: the CLI uses the keychain / credential helper and
        // ~/.ssh config, so it authenticates against private remotes. `token`
        // picks the repo's bound gh account rather than gh's active account.
        guard runGit(["fetch", "origin"], at: url, token: token) != nil else {
            throw NSError(
                domain: "GitService", code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't fetch origin — check your network connection and git credentials."]
            )
        }

        // Merge the freshly-fetched base into the current checkout. `--no-edit`
        // accepts the default merge message non-interactively; a fast-forward
        // (the common "behind only" case) just advances HEAD. A non-zero exit
        // means conflicts or a dirty tree blocked the merge — surface it so the
        // pill stays put and the user can resolve and retry.
        guard runGit(["merge", "--no-edit", "origin/\(defaultBranch)"], at: url) != nil else {
            throw NSError(
                domain: "GitService", code: 3,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't merge origin/\(defaultBranch) — resolve conflicts or commit local changes, then retry."]
            )
        }
    }

    /// Count of dirty files (anything that isn't `.current` or `.ignored`)
    /// at `url`. Used by hardResetToOrigin to record the pre-reset state.
    private func preResetDirtyFileCount(at url: URL) -> Int {
        do {
            let repo = try SwiftGitX.Repository(
                at: url, createIfNotExists: false
            )
            let entries = try repo.status(
                options: SwiftGitX.StatusOption.default
            )
            return entries.filter { entry in
                entry.status.contains { status in
                    switch status {
                    case .current, .ignored:
                        return false
                    default:
                        return true
                    }
                }
            }.count
        } catch {
            return 0
        }
    }

    /// Detect the repo's default branch using the same fallback chain
    /// the user would use manually:
    ///   1. `git symbolic-ref refs/remotes/origin/HEAD` — the canonical answer
    ///      if `origin/HEAD` is set (which it is on a fresh `git clone`).
    ///   2. `refs/remotes/origin/main` exists?
    ///   3. `refs/remotes/origin/master` exists?
    ///   4. Else: `"main"`.
    ///
    /// Returns the short branch name (e.g. `"main"`, not `"origin/main"`).
    private func detectDefaultBranch(at url: URL) -> String {
        // Step 1: try origin/HEAD
        if let raw = runGit(
            ["symbolic-ref", "refs/remotes/origin/HEAD"], at: url
        ) {
            // raw is e.g. "refs/remotes/origin/main"
            let prefix = "refs/remotes/origin/"
            if raw.hasPrefix(prefix) {
                let name = String(raw.dropFirst(prefix.count))
                if !name.isEmpty { return name }
            }
        }

        // Step 2: probe origin/main
        if runGit(
            ["show-ref", "--verify", "--quiet", "refs/remotes/origin/main"],
            at: url
        ) != nil {
            return "main"
        }

        // Step 3: probe origin/master
        if runGit(
            ["show-ref", "--verify", "--quiet", "refs/remotes/origin/master"],
            at: url
        ) != nil {
            return "master"
        }

        // Step 4: fall back to "main"
        return "main"
    }

    /// Returns the 7-char short SHA of `origin/<defaultBranch>` if it
    /// exists. Empty string if the remote ref is missing (e.g. local-only
    /// repo). Mirrors `git rev-parse --short origin/<defaultBranch>`.
    private func originDefaultShortSha(
        at url: URL, defaultBranch: String
    ) -> String {
        guard let raw = runGit(
            ["rev-parse", "--short", "origin/\(defaultBranch)"],
            at: url
        ) else { return "" }
        return raw
    }

    // MARK: - Subprocess helpers

    /// Run `git` with the given arguments against `cwd`. Returns trimmed
    /// stdout on success, nil on any error (missing ref, no remote, etc.).
    /// This is intentionally lossy: most callers in this file treat absence
    /// as "zero" rather than propagating the error.
    ///
    /// `token`, when non-nil, is exported as `GH_TOKEN` so the `gh auth
    /// git-credential` helper authenticates as the repo's bound account rather
    /// than gh's globally-active account — required for network operations
    /// (`fetch`) against a private remote that the active account can't see.
    private func runGit(_ args: [String], at cwd: URL, token: String? = nil) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", cwd.path] + args
        // Finder-launched GUI apps inherit only the minimal launchd PATH; add
        // Homebrew dirs so a Homebrew-only `git` still resolves. See SubprocessPATH.
        // A non-nil token is injected as GH_TOKEN so the credential helper picks
        // the right account.
        p.environment = SubprocessPATH.environment(
            extra: token.map { ["GH_TOKEN": $0] } ?? [:]
        )
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
