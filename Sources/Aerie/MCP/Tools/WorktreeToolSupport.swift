import Foundation

/// Resolve `repo_id` + `worktree_path` params into a validated worktree URL.
/// Throws `-32602` for an unknown repo, and `-32602` when `worktree_path` is
/// not one of the repo's actual worktrees — so a destructive op can't target an
/// arbitrary directory. Returns the repo and the worktree URL.
func resolveWorktree(
    params: JSONValue?, db: AppDatabase, git: any GitService
) async throws -> (repo: Repository, worktree: URL) {
    let repoId = try uuidParam(params, key: "repo_id")
    let path = try stringParam(params, key: "worktree_path")
    guard let repo = try await db.repos.find(id: repoId) else {
        throw JSONRPCError(code: -32602, message: "Unknown repo_id", data: nil)
    }
    let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    let rows = await git.worktrees(mainWorktreeAt: repo.localPath)
    guard rows.contains(where: { $0.path.resolvingSymlinksInPath().path == target }) else {
        throw JSONRPCError(code: -32602, message: "worktree_path is not a worktree of this repo", data: nil)
    }
    return (repo, URL(fileURLWithPath: path))
}
