import XCTest
import GRDB
@testable import Aerie

final class SettingsDAOTests: XCTestCase {
    // MARK: - Helpers

    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    // MARK: - Tests

    func test_setAndGetRaw() async throws {
        let db = try makeDB()
        try await db.settings.set("theme", "{\"mode\":\"dark\"}")
        let got = try await db.settings.get("theme")
        XCTAssertEqual(got, "{\"mode\":\"dark\"}")
    }

    func test_get_returnsNilForMissing() async throws {
        let db = try makeDB()
        let got = try await db.settings.get("does-not-exist")
        XCTAssertNil(got)
    }

    func test_setReplaces_existingValue() async throws {
        let db = try makeDB()
        try await db.settings.set("k", "v1")
        try await db.settings.set("k", "v2")
        let got = try await db.settings.get("k")
        XCTAssertEqual(got, "v2")
    }

    func test_setBool_roundtrip() async throws {
        let db = try makeDB()
        try await db.settings.setBool("flag", true)
        let gotTrue = try await db.settings.getBool("flag")
        XCTAssertEqual(gotTrue, true)

        try await db.settings.setBool("flag", false)
        let gotFalse = try await db.settings.getBool("flag")
        XCTAssertEqual(gotFalse, false)
    }

    func test_getBool_returnsNilForMissingOrInvalid() async throws {
        let db = try makeDB()
        let missing = try await db.settings.getBool("missing")
        XCTAssertNil(missing)

        try await db.settings.set("garbage", "not-a-bool")
        let garbage = try await db.settings.getBool("garbage")
        XCTAssertNil(garbage)
    }

    func test_setInt_roundtrip() async throws {
        let db = try makeDB()
        try await db.settings.setInt("count", 42)
        let got = try await db.settings.getInt("count")
        XCTAssertEqual(got, 42)
    }

    func test_getInt_returnsNilForMissingOrInvalid() async throws {
        let db = try makeDB()
        let missing = try await db.settings.getInt("missing")
        XCTAssertNil(missing)

        try await db.settings.set("garbage", "abc")
        let garbage = try await db.settings.getInt("garbage")
        XCTAssertNil(garbage)
    }

    func test_setString_roundtrip() async throws {
        let db = try makeDB()
        try await db.settings.setString("name", "Aerie")
        let got = try await db.settings.getString("name")
        XCTAssertEqual(got, "Aerie")
    }

    func test_delete_removesKey() async throws {
        let db = try makeDB()
        try await db.settings.setString("pr_publish.template", "custom")
        try await db.settings.delete("pr_publish.template")
        let got = try await db.settings.getString("pr_publish.template")
        XCTAssertNil(got)
    }

    func test_delete_missingKey_isNoop() async throws {
        let db = try makeDB()
        try await db.settings.delete("never.existed")   // must not throw
        let got = try await db.settings.get("never.existed")
        XCTAssertNil(got)
    }
}
