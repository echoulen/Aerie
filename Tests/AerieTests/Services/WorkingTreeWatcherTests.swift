import XCTest
@testable import Aerie

/// The FSEvents-backed change source that gates git status reads: a repo whose
/// working tree hasn't changed since the last read is skipped, so an idle
/// fleet costs nothing per tick (a UE project with 60k ignored files took
/// libgit2 ~8 s per status walk, every 30 s).
final class WorkingTreeWatcherTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs.removeAll()
    }

    private func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wtw-" + UUID().uuidString)
        tempURLs.append(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Polls `consumeChange` until it reports a change or `timeout` elapses.
    private func waitForChange(_ watcher: WorkingTreeWatcher, at url: URL,
                               timeout: TimeInterval = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if watcher.consumeChange(at: url) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    func test_firstConsume_reportsChanged_thenQuietUntilAWrite() async throws {
        let dir = try makeTempDir()
        let watcher = WorkingTreeWatcher()
        defer { watcher.stopAll() }

        XCTAssertTrue(watcher.consumeChange(at: dir), "a never-read tree must be read once")
        // Let the stream settle: a freshly started stream can replay the
        // directory's creation.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        _ = watcher.consumeChange(at: dir)
        XCTAssertFalse(watcher.consumeChange(at: dir), "nothing happened since the last consume")

        try "x".write(to: dir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let changed = await waitForChange(watcher, at: dir)
        XCTAssertTrue(changed, "a write inside the tree must surface as a change")
        XCTAssertFalse(watcher.consumeChange(at: dir), "consume clears the flag")
    }

    func test_writeInNestedDirectory_isSeen() async throws {
        let dir = try makeTempDir()
        let nested = dir.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let watcher = WorkingTreeWatcher()
        defer { watcher.stopAll() }
        _ = watcher.consumeChange(at: dir)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        _ = watcher.consumeChange(at: dir)

        try "y".write(to: nested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)
        let changed = await waitForChange(watcher, at: dir)
        XCTAssertTrue(changed)
    }

    func test_markAllChanged_forcesTheNextRead() throws {
        let a = try makeTempDir(), b = try makeTempDir()
        let watcher = WorkingTreeWatcher()
        defer { watcher.stopAll() }
        _ = watcher.consumeChange(at: a)
        _ = watcher.consumeChange(at: b)
        XCTAssertFalse(watcher.consumeChange(at: a))

        watcher.markAllChanged()
        XCTAssertTrue(watcher.consumeChange(at: a))
        XCTAssertTrue(watcher.consumeChange(at: b))
        XCTAssertFalse(watcher.consumeChange(at: a))
    }

    func test_pathsAreIndependent() throws {
        let a = try makeTempDir(), b = try makeTempDir()
        let watcher = WorkingTreeWatcher()
        defer { watcher.stopAll() }
        XCTAssertTrue(watcher.consumeChange(at: a))
        XCTAssertTrue(watcher.consumeChange(at: b), "each tree gets its own first read")
        XCTAssertFalse(watcher.consumeChange(at: a))
    }
}
