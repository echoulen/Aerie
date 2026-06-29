import XCTest
@testable import Aerie

@MainActor
final class LastApproverStoreTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs.removeAll()
    }

    private func makeStore() throws -> LastApproverStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return LastApproverStore(settings: try AppDatabase(url: url).settings)
    }

    func test_recordThenLogin_roundTrips() async throws {
        let store = try makeStore()
        let repo = UUID()
        await store.record("teammate", forRepo: repo)
        let got = await store.login(forRepo: repo)
        XCTAssertEqual(got, "teammate")
    }

    func test_login_absent_returnsNil() async throws {
        let store = try makeStore()
        let got = await store.login(forRepo: UUID())
        XCTAssertNil(got)
    }

    func test_record_isPerRepo() async throws {
        let store = try makeStore()
        let repoA = UUID(), repoB = UUID()
        await store.record("alice", forRepo: repoA)
        await store.record("bob", forRepo: repoB)
        let a = await store.login(forRepo: repoA)
        let b = await store.login(forRepo: repoB)
        XCTAssertEqual(a, "alice")
        XCTAssertEqual(b, "bob")
    }

    func test_record_overwrites() async throws {
        let store = try makeStore()
        let repo = UUID()
        await store.record("alice", forRepo: repo)
        await store.record("bob", forRepo: repo)
        let got = await store.login(forRepo: repo)
        XCTAssertEqual(got, "bob")
    }
}
