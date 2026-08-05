import XCTest
@testable import Aerie

@MainActor
final class PRActionStoreTests: XCTestCase {
    private func repo(id: UUID = UUID()) -> Repository {
        Repository(id: id, name: "aerie", localPath: URL(fileURLWithPath: "/tmp/aerie"),
                   githubOwner: "echoulen", githubRepo: "aerie", defaultBranch: "main",
                   primaryAccountId: UUID(), sortOrder: 0, hidden: false)
    }
    private func prRow(number: Int = 1, repo: Repository? = nil) -> PRRow {
        let r = repo ?? self.repo()
        let pr = PullRequest(id: UUID(), repoId: r.id, number: number, title: "T",
            authorLogin: "octocat", sourceBranch: "feat/x", isMine: false, state: .open,
            ciState: .success, reviewState: .reviewRequired, labels: [],
            htmlUrl: URL(string: "https://e.com")!, updatedAt: Date(timeIntervalSince1970: 1))
        return PRRow(pr: pr, repo: r, localState: nil)
    }

    /// Polls `phase` until it's no longer `.running`, bounded so a bug can't hang the test.
    private func settle(_ store: PRActionStore, _ kind: PRActionStore.Kind, _ row: PRRow) async {
        for _ in 0..<200 {
            if case .running = store.phase(kind, for: row) {
                await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000)
            } else { return }
        }
    }

    func test_start_success_settlesToIdle() async {
        let store = PRActionStore()
        let row = prRow()
        store.start(.merge, row: row) { nil }
        await settle(store, .merge, row)
        XCTAssertEqual(store.phase(.merge, for: row), .idle)
    }

    func test_start_failure_setsFailedPhase() async {
        let store = PRActionStore()
        let row = prRow()
        store.start(.merge, row: row) { "conflict" }
        await settle(store, .merge, row)
        XCTAssertEqual(store.phase(.merge, for: row), .failed("conflict"))
    }

    func test_start_reentry_onSameKey_isNoOp() async {
        let store = PRActionStore()
        let row = prRow()
        var calls = 0
        // First call never resolves on its own — hold it `.running` so the
        // second `start` lands while it's still in flight.
        let gate = AsyncGate()
        store.start(.merge, row: row) { calls += 1; await gate.wait(); return nil }
        // Give the first Task a tick to insert into `running` before the second call.
        try? await Task.sleep(nanoseconds: 5_000_000)
        store.start(.merge, row: row) { calls += 1; return nil }
        await gate.open()
        await settle(store, .merge, row)
        XCTAssertEqual(calls, 1, "second start() while the first is running must be a no-op")
    }

    func test_differentKinds_onSameRow_runIndependently() async {
        let store = PRActionStore()
        let row = prRow()
        store.start(.merge, row: row) { "merge failed" }
        store.start(.checkout, row: row) { nil }
        await settle(store, .merge, row)
        await settle(store, .checkout, row)
        XCTAssertEqual(store.phase(.merge, for: row), .failed("merge failed"))
        XCTAssertEqual(store.phase(.checkout, for: row), .idle)
    }

    func test_retry_reinvokesTheSameCapturedWork() async {
        let store = PRActionStore()
        let row = prRow()
        var attempt = 0
        store.start(.merge, row: row) { attempt += 1; return attempt == 1 ? "first fails" : nil }
        await settle(store, .merge, row)
        XCTAssertEqual(store.phase(.merge, for: row), .failed("first fails"))
        store.retry(.merge, row: row)
        await settle(store, .merge, row)
        XCTAssertEqual(store.phase(.merge, for: row), .idle)
        XCTAssertEqual(attempt, 2)
    }

    func test_dismiss_clearsFailedPhaseToIdle() async {
        let store = PRActionStore()
        let row = prRow()
        store.start(.merge, row: row) { "boom" }
        await settle(store, .merge, row)
        store.dismiss(.merge, row: row)
        XCTAssertEqual(store.phase(.merge, for: row), .idle)
    }

    func test_key_isStableAcrossRowInstancesWithSamePRNumber() async {
        // Simulates a background refresh re-fetching the PR: a fresh
        // `PullRequest.id` (new UUID) but the same repo id + PR number must
        // still resolve to the same phase.
        let store = PRActionStore()
        let repoId = UUID()
        let repoA = repo(id: repoId)
        let rowBeforeRefresh = prRow(number: 7, repo: repoA)
        store.start(.merge, row: rowBeforeRefresh) { "x" }
        await settle(store, .merge, rowBeforeRefresh)
        let rowAfterRefresh = prRow(number: 7, repo: repoA) // fresh PullRequest.id
        XCTAssertEqual(store.phase(.merge, for: rowAfterRefresh), .failed("x"))
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
