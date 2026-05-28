import XCTest
@testable import Aerie

final class DiscoveryFileWriterTests: XCTestCase {
    private var tmpDir: URL!
    private var tmpPath: URL!

    override func setUpWithError() throws {
        // Unique tmp dir per test so parallel test runs don't collide.
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        tmpDir = base.appendingPathComponent("DiscoveryFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        tmpPath = tmpDir.appendingPathComponent("mcp.json")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try FileManager.default.removeItem(at: tmpDir)
        }
    }

    func test_write_createsFile_withMode0600() throws {
        let writer = DiscoveryFileWriter(path: tmpPath)
        try writer.write(endpoint: "http://127.0.0.1:1234/mcp", token: "abc")

        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpPath.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: tmpPath.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        XCTAssertEqual(Int(perms), 0o600, "expected mode 0600, got 0o\(String(perms, radix: 8))")
    }

    func test_write_containsExpectedKeys() throws {
        let writer = DiscoveryFileWriter(path: tmpPath)
        try writer.write(endpoint: "http://127.0.0.1:1234/mcp", token: "the-token")

        let data = try Data(contentsOf: tmpPath)
        let decoded = try JSONDecoder().decode(DiscoveryFileWriter.DiscoveryPayload.self, from: data)
        XCTAssertEqual(decoded.endpoint, "http://127.0.0.1:1234/mcp")
        XCTAssertEqual(decoded.token, "the-token")
        XCTAssertEqual(decoded.pid, Int(ProcessInfo.processInfo.processIdentifier))
        // started_at is a Unix timestamp — sanity-check it's recent.
        let now = Date().timeIntervalSince1970
        XCTAssertGreaterThan(decoded.started_at, now - 60)
        XCTAssertLessThanOrEqual(decoded.started_at, now + 1)
    }

    func test_clear_removesFile() throws {
        let writer = DiscoveryFileWriter(path: tmpPath)
        try writer.write(endpoint: "http://127.0.0.1:1234/mcp", token: "abc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpPath.path))

        try writer.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpPath.path))
    }

    func test_clear_isIdempotent() throws {
        let writer = DiscoveryFileWriter(path: tmpPath)
        XCTAssertNoThrow(try writer.clear()) // no file yet
        try writer.write(endpoint: "x", token: "y")
        try writer.clear()
        XCTAssertNoThrow(try writer.clear()) // already cleared
    }

    func test_write_isAtomic_secondWriteReplacesFirst() throws {
        let writer = DiscoveryFileWriter(path: tmpPath)
        try writer.write(endpoint: "http://127.0.0.1:1234/mcp", token: "first")
        try writer.write(endpoint: "http://127.0.0.1:5678/mcp", token: "second")

        let data = try Data(contentsOf: tmpPath)
        let decoded = try JSONDecoder().decode(DiscoveryFileWriter.DiscoveryPayload.self, from: data)
        XCTAssertEqual(decoded.endpoint, "http://127.0.0.1:5678/mcp")
        XCTAssertEqual(decoded.token, "second")

        // The tmp sibling file must not linger after the move.
        let tmp = tmpPath.appendingPathExtension("tmp")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tmp.path),
            "expected tmp file to be moved into place, not left behind"
        )
    }
}
