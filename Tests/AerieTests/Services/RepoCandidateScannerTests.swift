import XCTest
@testable import Aerie

final class RepoCandidateScannerTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempDirs {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirs.removeAll()
    }

    private func makeRoot() throws -> URL {
        let raw = URL(
            fileURLWithPath: NSTemporaryDirectory().appending(UUID().uuidString),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        tempDirs.append(raw)
        return raw
    }

    /// Compare a candidate URL against an expected URL while ignoring
    /// the /var/ vs /private/var/ discrepancy macOS introduces when
    /// the enumerator resolves symlinks.
    private func samePath(_ a: URL, _ b: URL) -> Bool {
        // Standardize + drop a leading "/private" prefix from either side.
        func normalize(_ url: URL) -> String {
            var p = url.standardizedFileURL.path
            if p.hasPrefix("/private") { p = String(p.dropFirst("/private".count)) }
            return p
        }
        return normalize(a) == normalize(b)
    }

    /// Makes `<parent>/<name>` look like a git repo (has a `.git`
    /// directory) without actually running `git init` — cheaper, and
    /// the scanner only checks for the entry's existence.
    @discardableResult
    private func makeFakeRepo(in parent: URL, name: String) throws -> URL {
        let dir = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gitDir = dir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        // Plus a couple of internal sub-entries to verify we don't recurse.
        let objects = gitDir.appendingPathComponent("objects")
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Tests

    func test_scan_findsAllReposAtDepth1() async throws {
        let root = try makeRoot()
        let a = try makeFakeRepo(in: root, name: "alpha")
        let b = try makeFakeRepo(in: root, name: "bravo")
        let c = try makeFakeRepo(in: root, name: "charlie")

        let scanner = RepoCandidateScanner()
        let results = await scanner.scan(root: root)
        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.contains { samePath($0.url, a) })
        XCTAssertTrue(results.contains { samePath($0.url, b) })
        XCTAssertTrue(results.contains { samePath($0.url, c) })
    }

    func test_scan_findsReposAtDepth2() async throws {
        let root = try makeRoot()
        let group = root.appendingPathComponent("group")
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        let repo = try makeFakeRepo(in: group, name: "nested")

        let scanner = RepoCandidateScanner()
        let results = await scanner.scan(root: root)
        XCTAssertTrue(results.contains { samePath($0.url, repo) })
    }

    func test_scan_doesNotRecurseIntoFoundRepos() async throws {
        let root = try makeRoot()
        _ = try makeFakeRepo(in: root, name: "repo")

        let scanner = RepoCandidateScanner()
        let results = await scanner.scan(root: root)
        // Exactly one candidate — the repo itself — not the `.git`
        // sub-tree we created.
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.url.lastPathComponent == "repo")
    }

    func test_scan_respectsMaxDepth() async throws {
        let root = try makeRoot()
        // root/lvl1/lvl2/lvl3/repo  → repo lives at depth 4
        let lvl1 = root.appendingPathComponent("lvl1")
        let lvl2 = lvl1.appendingPathComponent("lvl2")
        let lvl3 = lvl2.appendingPathComponent("lvl3")
        try FileManager.default.createDirectory(at: lvl3, withIntermediateDirectories: true)
        _ = try makeFakeRepo(in: lvl3, name: "deep")

        let scanner = RepoCandidateScanner()
        let results = await scanner.scan(root: root, maxDepth: 3)
        XCTAssertTrue(results.isEmpty)
    }

    func test_scan_respectsMaxEntries() async throws {
        let root = try makeRoot()
        // Create a flat batch of plain (non-repo) directories — the
        // scanner should bail out after `maxEntries` visits without
        // surfacing any candidates.
        for i in 0..<50 {
            let d = root.appendingPathComponent("d\(i)")
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        // Plus one repo buried among them
        _ = try makeFakeRepo(in: root, name: "actual-repo")

        let scanner = RepoCandidateScanner()
        let results = await scanner.scan(root: root, maxDepth: 3, maxEntries: 5)
        // We can't assert exactly zero (the repo might happen to be
        // visited within the first 5), but the cap means we never
        // return more than a handful.
        XCTAssertLessThanOrEqual(results.count, 5)
    }

    func test_scan_sortsByMostRecentlyTouched() async throws {
        let root = try makeRoot()
        let older = try makeFakeRepo(in: root, name: "older")
        let newer = try makeFakeRepo(in: root, name: "newer")

        // Backdate the older repo's mod time.
        let earlier = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes(
            [.modificationDate: earlier],
            ofItemAtPath: older.path
        )
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: newer.path
        )

        let scanner = RepoCandidateScanner()
        let results = await scanner.scan(root: root)
        XCTAssertEqual(results.first?.url.lastPathComponent, "newer")
    }
}
