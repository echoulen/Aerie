import XCTest
@testable import Aerie

@MainActor
final class PRCreateStoreTests: XCTestCase {
    private func repoRow(repoId: UUID = UUID()) -> RepoRow {
        let repo = Repository(
            id: repoId, name: "aerie", localPath: URL(fileURLWithPath: "/tmp/aerie"),
            githubOwner: "echoulen", githubRepo: "aerie", defaultBranch: "main",
            primaryAccountId: UUID(), sortOrder: 0, hidden: false)
        return RepoRow(repo: repo, status: nil)
    }

    private func makeStore(
        run: @escaping (RepoRow, @escaping @Sendable (String) -> Void) async -> PRCreateOutcome,
        onCreated: @escaping () async -> Void = {},
        revertSeconds: TimeInterval = 0.05
    ) -> PRCreateStore {
        PRCreateStore(runCreate: run, onCreated: onCreated,
                      nothingToDoRevertSeconds: revertSeconds)
    }

    /// Waits until the phase leaves `.running` (or `.idle`, for revert tests).
    private func settle(_ store: PRCreateStore, _ row: RepoRow) async {
        for _ in 0..<200 {
            if case .running = store.phase(for: row) {
                await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000)
            } else { return }
        }
    }

    func test_created_setsDone_andFiresOnCreated() async {
        var createdFired = false
        let url = URL(string: "https://github.com/e/r/pull/9")!
        let store = makeStore(
            run: { _, _ in .created(prNumber: 9, url: url, summary: "s") },
            onCreated: { createdFired = true })
        let row = repoRow()
        store.start(row: row)
        await settle(store, row)
        guard case .done(let n, let u) = store.phase(for: row) else {
            return XCTFail("expected .done, got \(store.phase(for: row))")
        }
        XCTAssertEqual(n, 9); XCTAssertEqual(u, url)
        XCTAssertTrue(createdFired)
    }

    func test_failed_setsFailed_noOnCreated() async {
        var createdFired = false
        let store = makeStore(run: { _, _ in .failed("boom") },
                              onCreated: { createdFired = true })
        let row = repoRow()
        store.start(row: row)
        await settle(store, row)
        guard case .failed(let m) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(m, "boom")
        XCTAssertFalse(createdFired)
    }

    func test_nothingToDo_revertsToIdle() async {
        let store = makeStore(run: { _, _ in .nothingToDo(summary: "") })
        let row = repoRow()
        store.start(row: row)
        await settle(store, row)
        guard case .nothingToDo = store.phase(for: row) else { return XCTFail() }
        // Wait past the (shortened) revert delay.
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard case .idle = store.phase(for: row) else {
            return XCTFail("expected auto-revert to .idle")
        }
    }

    func test_restartDuringNothingToDo_getsFreshRevertWindow() async {
        let store = makeStore(run: { _, _ in .nothingToDo(summary: "") },
                              revertSeconds: 0.3)
        let row = repoRow()
        store.start(row: row)
        await settle(store, row)                        // → .nothingToDo (t≈0)
        try? await Task.sleep(nanoseconds: 100_000_000) // t≈0.1
        store.start(row: row)                           // must cancel timer 1
        await settle(store, row)                        // → .nothingToDo again
        // t≈0.35: timer 1 (t=0.3) would have fired by now — the phase must
        // still be .nothingToDo because timer 2 (t≈0.4+) owns the window.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard case .nothingToDo = store.phase(for: row) else {
            return XCTFail("stale timer truncated the second window")
        }
        // t≈0.6: timer 2 has fired — now it reverts.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard case .idle = store.phase(for: row) else {
            return XCTFail("expected revert to .idle after the fresh window")
        }
    }

    func test_progressLines_accumulate_whileRunning() async {
        let gate = AsyncGate()
        let store = makeStore(run: { _, onLine in
            onLine("step one"); onLine("step two")
            await gate.wait()
            return .failed("end")
        })
        let row = repoRow()
        store.start(row: row)
        // Let the onLine hops land on the main actor.
        for _ in 0..<50 {
            if case .running(let lines) = store.phase(for: row), lines.count == 2 { break }
            await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .running(let lines) = store.phase(for: row) else { return XCTFail() }
        XCTAssertEqual(lines, ["step one", "step two"])
        XCTAssertTrue(store.isRunning(for: row))
        await gate.open()
        await settle(store, row)
    }

    func test_reentry_secondStartIgnoredWhileRunning() async {
        let gate = AsyncGate()
        let calls = Counter()
        let store = makeStore(run: { _, _ in
            calls.increment()
            await gate.wait()
            return .failed("end")
        })
        let row = repoRow()
        store.start(row: row)
        store.start(row: row)   // ignored — already running
        await gate.open()
        await settle(store, row)
        XCTAssertEqual(calls.value, 1)
    }

    func test_phases_keyedPerRepo() async {
        let store = makeStore(run: { row, _ in
            row.repo.githubRepo == "aerie"
                ? .failed("a") : .nothingToDo(summary: "")
        })
        let rowA = repoRow()
        store.start(row: rowA)
        await settle(store, rowA)
        let rowB = repoRow(repoId: UUID())
        XCTAssertEqual(store.phase(for: rowB), .idle)
    }
}

/// Reusable async latch: `wait()` suspends until `open()` is called.
private actor AsyncGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        for w in waiters { w.resume() }
        waiters.removeAll()
    }
}

/// Thread-safe call counter for closure-invocation assertions.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
