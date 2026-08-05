import XCTest
@testable import Aerie

@MainActor
final class RepoActionStoreTests: XCTestCase {
    private func repo(id: UUID = UUID()) -> Repository {
        Repository(id: id, name: "aerie", localPath: URL(fileURLWithPath: "/tmp/aerie"),
                   githubOwner: "echoulen", githubRepo: "aerie", defaultBranch: "main",
                   primaryAccountId: UUID(), sortOrder: 0, hidden: false)
    }
    private func worktree(path: String = "/tmp/aerie-wt") -> WorktreeRow {
        WorktreeRow(path: URL(fileURLWithPath: path), branchLabel: "feat/x",
                    isDetached: false, isDirty: false, dirtyFileCount: 0, prunable: false)
    }

    private func settle(_ store: RepoActionStore, _ kind: RepoActionStore.Kind, _ t: RepoActionStore.Target) async {
        for _ in 0..<200 {
            if case .running = store.phase(kind, for: t) {
                await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000)
            } else { return }
        }
    }

    func test_repoScoped_success_settlesToIdle() async {
        let store = RepoActionStore()
        let target = RepoActionStore.Target.repo(repo())
        store.start(.hardReset, target: target) { nil }
        await settle(store, .hardReset, target)
        XCTAssertEqual(store.phase(.hardReset, for: target), .idle)
    }

    func test_worktreeScoped_failure_setsFailedPhase() async {
        let store = RepoActionStore()
        let target = RepoActionStore.Target.worktree(worktree())
        store.start(.deleteWorktree, target: target) { "in use" }
        await settle(store, .deleteWorktree, target)
        XCTAssertEqual(store.phase(.deleteWorktree, for: target), .failed("in use"))
    }

    func test_repoAndWorktreeTargets_withSamePathPrefix_dontCollide() async {
        // A repo id and an unrelated worktree path are never equal strings,
        // but this pins down that the two Target cases key independently
        // even for the same underlying repo.
        let store = RepoActionStore()
        let r = repo()
        let wt = worktree()
        store.start(.hardReset, target: .repo(r)) { "repo failed" }
        store.start(.discardWorktree, target: .worktree(wt)) { nil }
        await settle(store, .hardReset, .repo(r))
        await settle(store, .discardWorktree, .worktree(wt))
        XCTAssertEqual(store.phase(.hardReset, for: .repo(r)), .failed("repo failed"))
        XCTAssertEqual(store.phase(.discardWorktree, for: .worktree(wt)), .idle)
    }

    func test_reentry_onSameTarget_isNoOp() async {
        let store = RepoActionStore()
        let target = RepoActionStore.Target.repo(repo())
        var calls = 0
        let gate = AsyncGate()
        store.start(.discardUnstaged, target: target) { calls += 1; await gate.wait(); return nil }
        try? await Task.sleep(nanoseconds: 5_000_000)
        store.start(.discardUnstaged, target: target) { calls += 1; return nil }
        await gate.open()
        await settle(store, .discardUnstaged, target)
        XCTAssertEqual(calls, 1)
    }

    func test_retry_reinvokesSameWork() async {
        let store = RepoActionStore()
        let target = RepoActionStore.Target.worktree(worktree())
        var attempt = 0
        store.start(.mergeWorktree, target: target) { attempt += 1; return attempt == 1 ? "conflict" : nil }
        await settle(store, .mergeWorktree, target)
        store.retry(.mergeWorktree, target: target)
        await settle(store, .mergeWorktree, target)
        XCTAssertEqual(store.phase(.mergeWorktree, for: target), .idle)
        XCTAssertEqual(attempt, 2)
    }

    func test_dismiss_clearsFailedPhase() async {
        let store = RepoActionStore()
        let target = RepoActionStore.Target.repo(repo())
        store.start(.hardReset, target: target) { "boom" }
        await settle(store, .hardReset, target)
        store.dismiss(.hardReset, target: target)
        XCTAssertEqual(store.phase(.hardReset, for: target), .idle)
    }
}

/// Lets a test hold a `start` closure `.running` until it explicitly opens the
/// gate, so re-entrancy can be tested deterministically.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func open() { isOpen = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
