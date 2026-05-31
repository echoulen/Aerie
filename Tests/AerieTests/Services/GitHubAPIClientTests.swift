import XCTest
@testable import Aerie

// MARK: - URLProtocol stub

/// Single-threaded test-only URL protocol that lets each test install a
/// handler closure mapping `URLRequest -> (HTTPURLResponse, Data)`.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var requestCount: Int = 0

    static func reset() {
        handler = nil
        lastRequest = nil
        lastBody = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }

    override func startLoading() {
        // Capture the request (and body — URLProtocol consumes it from the
        // upload stream when the original `URLRequest.httpBody` was set via a
        // BodyStream, so we read from both pathways).
        Self.requestCount += 1
        Self.lastRequest = request
        if let body = request.httpBody {
            Self.lastBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = nil
        }

        guard let handler = Self.handler else {
            fatalError("StubURLProtocol.handler not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Tests

final class GitHubAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: listOpenPRs

    func test_listOpenPRs_decodesGraphQLResponse() async throws {
        let responseJSON = """
        {
          "data": {
            "repository": {
              "pullRequests": {
                "nodes": [
                  {
                    "id": "PR_kw1",
                    "number": 42,
                    "title": "Fix the thing",
                    "author": { "login": "carlos-li" },
                    "headRefName": "fix/the-thing",
                    "state": "OPEN",
                    "mergeable": "MERGEABLE",
                    "labels": { "nodes": [ { "name": "bug" }, { "name": "p1" } ] },
                    "commits": {
                      "nodes": [
                        { "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }
                      ]
                    },
                    "reviewDecision": "APPROVED",
                    "updatedAt": "2026-05-28T10:00:00Z",
                    "url": "https://github.com/acme/widgets/pull/42"
                  },
                  {
                    "id": "PR_kw2",
                    "number": 43,
                    "title": "Tweak the knob",
                    "author": { "login": "octocat" },
                    "headRefName": "octocat/tweak",
                    "state": "OPEN",
                    "mergeable": "UNKNOWN",
                    "labels": { "nodes": [] },
                    "commits": {
                      "nodes": [
                        { "commit": { "statusCheckRollup": { "state": "PENDING" } } }
                      ]
                    },
                    "reviewDecision": null,
                    "updatedAt": "2026-05-28T09:30:00Z",
                    "url": "https://github.com/acme/widgets/pull/43"
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
        let prs = try await client.listOpenPRs(
            owner: "acme",
            repo: "widgets",
            repoId: repoId,
            token: "ghp_test"
        )

        XCTAssertEqual(prs.count, 2)

        let p1 = prs[0]
        XCTAssertEqual(p1.repoId, repoId)
        XCTAssertEqual(p1.number, 42)
        XCTAssertEqual(p1.title, "Fix the thing")
        XCTAssertEqual(p1.authorLogin, "carlos-li")
        XCTAssertEqual(p1.sourceBranch, "fix/the-thing")
        XCTAssertEqual(p1.state, .open)
        XCTAssertEqual(p1.ciState, .success)
        XCTAssertEqual(p1.reviewState, .approved)
        XCTAssertEqual(p1.labels, ["bug", "p1"])
        XCTAssertEqual(p1.htmlUrl.absoluteString, "https://github.com/acme/widgets/pull/42")
        XCTAssertFalse(p1.isMine)

        let p2 = prs[1]
        XCTAssertEqual(p2.number, 43)
        XCTAssertEqual(p2.authorLogin, "octocat")
        XCTAssertEqual(p2.ciState, .pending)
        XCTAssertEqual(p2.reviewState, .reviewRequired)
        XCTAssertEqual(p2.labels, [])
    }

    func test_listOpenPRs_mapsApprovedBy() async throws {
        // A PR approved by `maja-c`, and one with no reviews. The approver's
        // login must flow through to `PullRequest.approvedBy` so the merge
        // dialog can render "approved by maja-c".
        let responseJSON = """
        {
          "data": {
            "repository": {
              "pullRequests": {
                "nodes": [
                  {
                    "id": "PR_a",
                    "number": 1,
                    "title": "Approved one",
                    "author": { "login": "carlos-li" },
                    "headRefName": "feat/a",
                    "state": "OPEN",
                    "mergeable": "MERGEABLE",
                    "labels": { "nodes": [] },
                    "commits": { "nodes": [] },
                    "reviewDecision": "APPROVED",
                    "reviews": { "nodes": [ { "author": { "login": "maja-c" } } ] },
                    "updatedAt": "2026-05-28T10:00:00Z",
                    "url": "https://github.com/acme/widgets/pull/1"
                  },
                  {
                    "id": "PR_b",
                    "number": 2,
                    "title": "No reviews",
                    "author": { "login": "octocat" },
                    "headRefName": "feat/b",
                    "state": "OPEN",
                    "mergeable": "UNKNOWN",
                    "labels": { "nodes": [] },
                    "commits": { "nodes": [] },
                    "reviewDecision": null,
                    "reviews": { "nodes": [] },
                    "updatedAt": "2026-05-28T09:00:00Z",
                    "url": "https://github.com/acme/widgets/pull/2"
                  }
                ]
              }
            }
          }
        }
        """
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responseJSON.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        let prs = try await client.listOpenPRs(
            owner: "acme", repo: "widgets", repoId: UUID(), token: "ghp_test"
        )

        XCTAssertEqual(prs[0].approvedBy, "maja-c")
        XCTAssertNil(prs[1].approvedBy, "a PR with no approving review has no approver")
    }

    func test_listOpenPRs_mapsDiffStats() async throws {
        // The PR's diff size (additions / deletions / changed files) must flow
        // through so the merge dialog can render "+312 -184 · 7 files".
        let responseJSON = """
        {
          "data": {
            "repository": {
              "pullRequests": {
                "nodes": [
                  {
                    "id": "PR_a",
                    "number": 1,
                    "title": "Big change",
                    "author": { "login": "carlos-li" },
                    "headRefName": "feat/a",
                    "state": "OPEN",
                    "mergeable": "MERGEABLE",
                    "labels": { "nodes": [] },
                    "commits": { "nodes": [] },
                    "reviewDecision": "APPROVED",
                    "mergeStateStatus": "CLEAN",
                    "additions": 312,
                    "deletions": 184,
                    "changedFiles": 7,
                    "updatedAt": "2026-05-28T10:00:00Z",
                    "url": "https://github.com/acme/widgets/pull/1"
                  }
                ]
              }
            }
          }
        }
        """
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responseJSON.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        let prs = try await client.listOpenPRs(
            owner: "acme", repo: "widgets", repoId: UUID(), token: "ghp_test"
        )

        XCTAssertEqual(prs[0].additions, 312)
        XCTAssertEqual(prs[0].deletions, 184)
        XCTAssertEqual(prs[0].changedFiles, 7)
        XCTAssertEqual(prs[0].mergeStateStatus, "CLEAN")
    }

    func test_listOpenPRs_sendsCorrectQuery() async throws {
        let responseJSON = """
        { "data": { "repository": { "pullRequests": { "nodes": [] } } } }
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
        _ = try await client.listOpenPRs(
            owner: "acme",
            repo: "widgets",
            repoId: UUID(),
            token: "ghp_secret"
        )

        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(req.url?.absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_secret")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let query = try XCTUnwrap(json?["query"] as? String)
        XCTAssertTrue(query.contains("pullRequests(states: OPEN"))
        XCTAssertTrue(query.contains("statusCheckRollup"))
        let variables = try XCTUnwrap(json?["variables"] as? [String: Any])
        XCTAssertEqual(variables["owner"] as? String, "acme")
        XCTAssertEqual(variables["repo"] as? String, "widgets")
    }

    func test_listOpenPRs_throwsNotVisibleWhenRepositoryNull() async throws {
        // GitHub's GraphQL returns HTTP 200 with `repository: null` when the
        // token can't see a (private) repo. That must surface as a 404
        // GitHubAPIError — not a decode crash — so the multi-account fallback
        // can advance to an account that *can* see the repo.
        let responseJSON = #"{ "data": { "repository": null } }"#
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
            _ = try await client.listOpenPRs(
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

    func test_listOpenPRs_throwsOnHTTPError() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let body = #"{"message":"Bad credentials"}"#
            return (response, Data(body.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        do {
            _ = try await client.listOpenPRs(
                owner: "acme",
                repo: "widgets",
                repoId: UUID(),
                token: "ghp_bad"
            )
            XCTFail("expected throw")
        } catch let error as GitHubAPIError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.message, "Bad credentials")
        }
    }

    // MARK: mergePR

    func test_mergePR_sendsPUTWithSquashAndReturnsResult() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let body = #"{"sha":"abc123","merged":true,"message":"Pull Request successfully merged"}"#
            return (response, Data(body.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        let result = try await client.mergePR(
            owner: "acme",
            repo: "widgets",
            number: 42,
            method: .squash,
            token: "ghp_merge"
        )

        XCTAssertEqual(result, MergeResult(sha: "abc123", merged: true))

        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(
            req.url?.absoluteString,
            "https://api.github.com/repos/acme/widgets/pulls/42/merge"
        )
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_merge")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["merge_method"] as? String, "squash")
    }

    func test_mergePR_throwsOnNotMergeable() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 405,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let body = #"{"message":"Pull Request is not mergeable"}"#
            return (response, Data(body.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        do {
            _ = try await client.mergePR(
                owner: "acme",
                repo: "widgets",
                number: 42,
                method: .merge,
                token: "ghp_test"
            )
            XCTFail("expected throw")
        } catch let error as GitHubAPIError {
            XCTAssertEqual(error.status, 405)
            XCTAssertEqual(error.message, "Pull Request is not mergeable")
        }
    }

    func test_mergePR_passesMergeMethodVerbatim() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let body = #"{"sha":"deadbeef","merged":true}"#
            return (response, Data(body.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        _ = try await client.mergePR(
            owner: "acme",
            repo: "widgets",
            number: 7,
            method: .rebase,
            token: "ghp_test"
        )

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["merge_method"] as? String, "rebase")
    }

    // MARK: rate-limit header tracking

    func test_listOpenPRs_recordsRateLimitHeaders() async throws {
        let responseJSON = """
        { "data": { "repository": { "pullRequests": { "nodes": [] } } } }
        """
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "x-ratelimit-remaining": "4321",
                    "x-ratelimit-reset": "1735000000",
                    "x-ratelimit-limit": "5000",
                ]
            )!
            return (response, Data(responseJSON.utf8))
        }

        let client = LiveGitHubAPIClient(session: makeStubSession())
        _ = try await client.listOpenPRs(
            owner: "acme",
            repo: "widgets",
            repoId: UUID(),
            token: "ghp_rl"
        )

        let snap = client.lastRateLimit(token: "ghp_rl")
        XCTAssertEqual(
            snap,
            RateLimitSnapshot(remaining: 4321, resetEpoch: 1_735_000_000, limit: 5000)
        )
    }

    func test_lastRateLimit_returnsNilForUntouchedToken() {
        let client = LiveGitHubAPIClient(session: makeStubSession())
        XCTAssertNil(client.lastRateLimit(token: "never_used"))
    }

    func test_listOpenPRs_handlesEmpty() async throws {
        let responseJSON = """
        { "data": { "repository": { "pullRequests": { "nodes": [] } } } }
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
        let prs = try await client.listOpenPRs(
            owner: "acme",
            repo: "widgets",
            repoId: UUID(),
            token: "ghp_test"
        )
        XCTAssertEqual(prs, [])
    }
}
