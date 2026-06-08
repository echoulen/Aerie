import XCTest
@testable import Aerie

final class GitHubAPIClientMergedPRTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func stub(_ json: String, status: Int = 200) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    func test_mergedPR_decodesMergedNode() async throws {
        stub("""
        { "data": { "repository": { "pullRequests": { "nodes": [
          { "number": 62,
            "url": "https://github.com/acme/widgets/pull/62",
            "headRefOid": "abc123def456",
            "mergedAt": "2026-05-28T10:00:00Z" }
        ] } } } }
        """)

        let client = LiveGitHubAPIClient(session: makeStubSession())
        let ref = try await client.mergedPR(
            owner: "acme", repo: "widgets", headBranch: "IOE-3017", token: "ghp_test"
        )
        let unwrapped = try XCTUnwrap(ref)
        XCTAssertEqual(unwrapped.number, 62)
        XCTAssertEqual(unwrapped.url.absoluteString, "https://github.com/acme/widgets/pull/62")
        XCTAssertEqual(unwrapped.headOid, "abc123def456")
    }

    func test_mergedPR_returnsNilWhenNoMergedPR() async throws {
        stub(#"{ "data": { "repository": { "pullRequests": { "nodes": [] } } } }"#)
        let client = LiveGitHubAPIClient(session: makeStubSession())
        let ref = try await client.mergedPR(
            owner: "acme", repo: "widgets", headBranch: "feat/none", token: "ghp_test"
        )
        XCTAssertNil(ref)
    }

    func test_mergedPR_throwsNotVisibleWhenRepositoryNull() async throws {
        stub(#"{ "data": { "repository": null } }"#)
        let client = LiveGitHubAPIClient(session: makeStubSession())
        do {
            _ = try await client.mergedPR(
                owner: "acme", repo: "private", headBranch: "x", token: "ghp_x"
            )
            XCTFail("expected throw")
        } catch let error as GitHubAPIError {
            XCTAssertEqual(error.status, 404)
        }
    }

    func test_mergedPR_sendsHeadRefNameAndMergedStateQuery() async throws {
        stub(#"{ "data": { "repository": { "pullRequests": { "nodes": [] } } } }"#)
        let client = LiveGitHubAPIClient(session: makeStubSession())
        _ = try await client.mergedPR(
            owner: "acme", repo: "widgets", headBranch: "IOE-3017", token: "ghp_secret"
        )

        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_secret")
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let query = try XCTUnwrap(obj?["query"] as? String)
        XCTAssertTrue(query.contains("states: MERGED"))
        XCTAssertTrue(query.contains("headRefName: $head"))
        let variables = try XCTUnwrap(obj?["variables"] as? [String: Any])
        XCTAssertEqual(variables["head"] as? String, "IOE-3017")
    }
}
