import Foundation

/// Where a worktree's checkout directory came from — inferred from its path.
/// `superset` worktrees live under `~/.superset/worktrees/`; everything else
/// is treated as `manual`. Drives the faint source tag in the rail.
enum WorktreeSource: Equatable {
    case superset, manual

    static func infer(from path: URL) -> WorktreeSource {
        path.path.contains("/.superset/worktrees/") ? .superset : .manual
    }
}

/// One worktree as the UI consumes it: a branch (or short SHA when detached),
/// its dirty state, the on-disk path, and whether git still lists it but the
/// directory is gone (`prunable`). Computed live — never persisted.
struct WorktreeRow: Identifiable, Equatable {
    var id: String { path.path }
    let path: URL
    let branchLabel: String
    let isDetached: Bool
    let isDirty: Bool
    let dirtyFileCount: Int
    let prunable: Bool

    var source: WorktreeSource { WorktreeSource.infer(from: path) }
}

/// The subset the porcelain parser produces (no dirty state yet — that needs a
/// libgit2 read per worktree, layered on in `LiveGitService`).
struct ParsedWorktree: Equatable {
    let path: URL
    let branchLabel: String
    let isDetached: Bool
    let prunable: Bool
}

/// Pure parser for `git worktree list --porcelain`. Records are blank-line
/// separated; the first record is always the main checkout (filtered out by
/// path). `bare` records are skipped. Detached worktrees report a 7-char short
/// SHA from their `HEAD` line in place of a branch name.
enum WorktreeParsing {
    static func parse(porcelain: String, mainWorktreePath: URL) -> [ParsedWorktree] {
        let mainResolved = mainWorktreePath.resolvingSymlinksInPath().path
        var result: [ParsedWorktree] = []

        for block in porcelain.components(separatedBy: "\n\n") {
            var path: String?
            var head: String?
            var branch: String?
            var detached = false
            var bare = false
            var prunable = false

            for raw in block.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(raw)
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    let heads = "refs/heads/"
                    branch = ref.hasPrefix(heads) ? String(ref.dropFirst(heads.count)) : ref
                } else if line == "detached" {
                    detached = true
                } else if line == "bare" {
                    bare = true
                } else if line.hasPrefix("prunable") {
                    prunable = true
                }
            }

            guard let p = path, !bare else { continue }
            if URL(fileURLWithPath: p).resolvingSymlinksInPath().path == mainResolved { continue }

            let label: String
            let isDetached: Bool
            if let b = branch, !detached {
                label = b
                isDetached = false
            } else {
                label = head.map { String($0.prefix(7)) } ?? ""
                isDetached = true
            }

            result.append(ParsedWorktree(
                path: URL(fileURLWithPath: p),
                branchLabel: label,
                isDetached: isDetached,
                prunable: prunable
            ))
        }
        return result
    }
}
