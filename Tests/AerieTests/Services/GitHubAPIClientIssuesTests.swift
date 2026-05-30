import XCTest
@testable import Aerie

/// Coverage for the issues side of `LiveGitHubAPIClient`. Reuses
/// `StubURLProtocol` / `makeStubSession()` from `GitHubAPIClientTests`.
final class GitHubAPIClientIssuesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func test_listOpenIssues_decodesGraphQLResponse_andComputesAssignedToMe() async throws {
        let responseJSON = """
        {
          "data": {
            "viewer": { "login": "carlos-li" },
            "repository": {
              "issues": {
                "nodes": [
                  {
                    "number": 148,
                    "title": "Polling backs off too aggressively after a 403",
                    "author": { "login": "maja-c" },
                    "labels": { "nodes": [ { "name": "bug", "color": "d73a4a" }, { "name": "polling", "color": "ededed" } ] },
                    "comments": { "totalCount": 6 },
                    "assignees": { "nodes": [ { "login": "carlos-li" } ] },
                    "updatedAt": "2026-05-28T10:00:00Z",
                    "url": "https://github.com/acme/widgets/issues/148"
                  },
                  {
                    "number": 204,
                    "title": "Glyph cache leaks under rapid re-render",
                    "author": { "login": "jens-h" },
                    "labels": { "nodes": [] },
                    "comments": { "totalCount": 0 },
                    "assignees": { "nodes": [ { "login": "someone-else" } ] },
                    "updatedAt": "2026-05-28T09:30:00Z",
                    "url": "https://github.com/acme/widgets/issues/204"
                  }
                ]
              }
            }
          }
        }
        """
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responseJSON.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        let repoId = UUID()
        let issues = try await client.listOpenIssues(
            owner: "acme",
            repo: "widgets",
            repoId: repoId,
            token: "ghp_test"
        )

        XCTAssertEqual(issues.count, 2)

        let i1 = issues[0]
        XCTAssertEqual(i1.repoId, repoId)
        XCTAssertEqual(i1.number, 148)
        XCTAssertEqual(i1.title, "Polling backs off too aggressively after a 403")
        XCTAssertEqual(i1.authorLogin, "maja-c")
        XCTAssertEqual(i1.labels, [IssueLabel(name: "bug", color: "d73a4a"), IssueLabel(name: "polling", color: "ededed")])
        XCTAssertEqual(i1.commentCount, 6)
        XCTAssertEqual(i1.htmlUrl.absoluteString, "https://github.com/acme/widgets/issues/148")
        XCTAssertTrue(i1.assignedToMe, "viewer is in the assignees")

        let i2 = issues[1]
        XCTAssertEqual(i2.number, 204)
        XCTAssertEqual(i2.commentCount, 0)
        XCTAssertEqual(i2.labels, [])
        XCTAssertFalse(i2.assignedToMe, "viewer is not in the assignees")
    }

    func test_listOpenIssues_sendsCorrectQuery() async throws {
        let responseJSON = """
        { "data": { "viewer": { "login": "x" }, "repository": { "issues": { "nodes": [] } } } }
        """
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        _ = try await client.listOpenIssues(
            owner: "acme",
            repo: "widgets",
            repoId: UUID(),
            token: "ghp_secret"
        )

        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(req.url?.absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_secret")

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let query = try XCTUnwrap(json?["query"] as? String)
        XCTAssertTrue(query.contains("issues(states: OPEN"))
        XCTAssertTrue(query.contains("viewer"))
        let variables = try XCTUnwrap(json?["variables"] as? [String: Any])
        XCTAssertEqual(variables["owner"] as? String, "acme")
        XCTAssertEqual(variables["repo"] as? String, "widgets")
    }

    func test_listOpenIssues_throwsNotVisibleWhenRepositoryNull() async throws {
        let responseJSON = #"{ "data": { "viewer": { "login": "x" }, "repository": null } }"#
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        do {
            _ = try await client.listOpenIssues(
                owner: "acme",
                repo: "private-widgets",
                repoId: UUID(),
                token: "ghp_unauthorized"
            )
            XCTFail("expected throw")
        } catch let error as GitHubAPIError {
            XCTAssertEqual(error.status, 404)
        }
    }
}
