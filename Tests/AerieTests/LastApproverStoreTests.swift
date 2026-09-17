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

    func test_recordThenLogins_roundTrips() async throws {
        let store = try makeStore()
        let repo = UUID()
        await store.record("teammate", forRepo: repo, author: "octocat")
        let got = await store.logins(forRepo: repo, author: "octocat")
        XCTAssertEqual(got, ["teammate", "teammate"])
    }

    func test_logins_absent_returnsEmpty() async throws {
        let store = try makeStore()
        let got = await store.logins(forRepo: UUID(), author: "octocat")
        XCTAssertEqual(got, [])
    }

    func test_record_isPerRepo() async throws {
        let store = try makeStore()
        let repoA = UUID(), repoB = UUID()
        await store.record("alice", forRepo: repoA, author: "octocat")
        await store.record("bob", forRepo: repoB, author: "octocat")
        let a = await store.logins(forRepo: repoA, author: "octocat")
        let b = await store.logins(forRepo: repoB, author: "octocat")
        XCTAssertEqual(a, ["alice", "alice"])
        XCTAssertEqual(b, ["bob", "bob"])
    }

    // Approving someone else's PR doesn't overwrite what this repo uses for
    // the author's own PRs; the repo-wide pick is only the fallback.
    func test_record_isPerAuthorWithinRepo() async throws {
        let store = try makeStore()
        let repo = UUID()
        await store.record("Jarvis-E", forRepo: repo, author: "echoulen")
        await store.record("echoulen", forRepo: repo, author: "dependabot")
        let own = await store.logins(forRepo: repo, author: "EchouLen")
        let stranger = await store.logins(forRepo: repo, author: "newcomer")
        XCTAssertEqual(own, ["Jarvis-E", "echoulen"])
        XCTAssertEqual(stranger, ["echoulen"])
    }

    func test_record_overwrites() async throws {
        let store = try makeStore()
        let repo = UUID()
        await store.record("alice", forRepo: repo, author: "octocat")
        await store.record("bob", forRepo: repo, author: "octocat")
        let got = await store.logins(forRepo: repo, author: "octocat")
        XCTAssertEqual(got, ["bob", "bob"])
    }
}
