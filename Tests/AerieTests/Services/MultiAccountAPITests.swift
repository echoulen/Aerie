import XCTest
@testable import Aerie

// MARK: - Mock GitHubAPIClient

/// In-memory client that returns canned results keyed by token. Lets us
/// exercise `MultiAccountAPI`'s fallback logic without driving URLSession.
actor StubGitHubAPIClient: GitHubAPIClient {
    enum Outcome {
        case prs([PullRequest])
        case merge(MergeResult)
        case apiError(GitHubAPIError)
        case throwError(Error)
    }

    /// Outcome per token, consumed in FIFO order so each call uses the next
    /// queued outcome. If the queue is empty for a token, `notFound`-style
    /// behaviour kicks in (test will fail-fast).
    var outcomesByToken: [String: [Outcome]] = [:]
    private(set) var callCount: Int = 0
    private(set) var tokensUsed: [String] = []
    private let rateLimits = RateLimitStore()

    func enqueue(_ outcome: Outcome, forToken token: String) {
        outcomesByToken[token, default: []].append(outcome)
    }

    func setRateLimit(_ snap: RateLimitSnapshot, forToken token: String) {
        rateLimits.set(token, snap)
    }

    private func consume(token: String) throws -> Outcome {
        callCount += 1
        tokensUsed.append(token)
        guard var queue = outcomesByToken[token], !queue.isEmpty else {
            throw GitHubAPIError(status: -1, message: "no canned outcome for token \(token)")
        }
        let next = queue.removeFirst()
        outcomesByToken[token] = queue
        return next
    }

    func listOpenPRs(
        owner: String,
        repo: String,
        repoId: UUID,
        token: String
    ) async throws -> [PullRequest] {
        let outcome = try consume(token: token)
        switch outcome {
        case .prs(let prs): return prs
        case .apiError(let err): throw err
        case .throwError(let err): throw err
        case .merge:
            throw GitHubAPIError(status: -1, message: "wrong outcome type for listOpenPRs")
        }
    }

    func mergePR(
        owner: String,
        repo: String,
        number: Int,
        method: MergeMethod,
        token: String
    ) async throws -> MergeResult {
        let outcome = try consume(token: token)
        switch outcome {
        case .merge(let r): return r
        case .apiError(let err): throw err
        case .throwError(let err): throw err
        case .prs:
            throw GitHubAPIError(status: -1, message: "wrong outcome type for mergePR")
        }
    }

    nonisolated func lastRateLimit(token: String) -> RateLimitSnapshot? {
        rateLimits.get(token)
    }
}

// MARK: - Tests

final class MultiAccountAPITests: XCTestCase {
    func test_listOpenPRs_primarySucceeds() async throws {
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "primary_tok"
        let secondaryToken = "secondary_tok"
        let repoId = UUID()
        let pr = makePR(repoId: repoId, number: 1)

        let stub = StubGitHubAPIClient()
        await stub.enqueue(.prs([pr]), forToken: primaryToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] }
        )

        let result = try await api.listOpenPRs(
            owner: "acme",
            repo: "widgets",
            repoId: repoId
        )
        XCTAssertEqual(result.value, [pr])
        XCTAssertEqual(result.successfulAccountId, primary)
        let count = await stub.callCount
        XCTAssertEqual(count, 1)
    }

    func test_listOpenPRs_fallsBackOn401() async throws {
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "bad_tok"
        let secondaryToken = "good_tok"
        let repoId = UUID()
        let pr = makePR(repoId: repoId, number: 2)

        let stub = StubGitHubAPIClient()
        await stub.enqueue(
            .apiError(GitHubAPIError(status: 401, message: "Bad credentials")),
            forToken: primaryToken
        )
        await stub.enqueue(.prs([pr]), forToken: secondaryToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] }
        )

        let result = try await api.listOpenPRs(
            owner: "acme",
            repo: "widgets",
            repoId: repoId
        )
        XCTAssertEqual(result.value, [pr])
        XCTAssertEqual(result.successfulAccountId, secondary)
        let tokensUsed = await stub.tokensUsed
        XCTAssertEqual(tokensUsed, [primaryToken, secondaryToken])
    }

    func test_listOpenPRs_throwsAfterAllFail() async throws {
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "bad1"
        let secondaryToken = "bad2"

        let stub = StubGitHubAPIClient()
        await stub.enqueue(
            .apiError(GitHubAPIError(status: 401, message: "Bad")),
            forToken: primaryToken
        )
        await stub.enqueue(
            .apiError(GitHubAPIError(status: 403, message: "Forbidden")),
            forToken: secondaryToken
        )

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] }
        )

        do {
            _ = try await api.listOpenPRs(
                owner: "acme",
                repo: "widgets",
                repoId: UUID()
            )
            XCTFail("expected throw")
        } catch let error as GitHubAPIError {
            // Last error wins.
            XCTAssertEqual(error.status, 403)
            XCTAssertEqual(error.message, "Forbidden")
        }
    }

    func test_listOpenPRs_doesNotFallBackOnNetworkError() async throws {
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "tok1"
        let secondaryToken = "tok2"

        let stub = StubGitHubAPIClient()
        await stub.enqueue(
            .throwError(URLError(.notConnectedToInternet)),
            forToken: primaryToken
        )
        // Secondary would succeed if we fell back — but we shouldn't.
        await stub.enqueue(.prs([]), forToken: secondaryToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] }
        )

        do {
            _ = try await api.listOpenPRs(
                owner: "acme",
                repo: "widgets",
                repoId: UUID()
            )
            XCTFail("expected throw")
        } catch is URLError {
            // expected — propagated without fallback
        }

        let count = await stub.callCount
        XCTAssertEqual(count, 1, "should only have called the primary, no fallback for network errors")
    }

    // MARK: rate-limit

    func test_multiAccount_rateLimitForAccount_returnsSnapshot() async throws {
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "primary_tok"
        let secondaryToken = "secondary_tok"
        let repoId = UUID()

        let stub = StubGitHubAPIClient()
        let snap = RateLimitSnapshot(remaining: 1234, resetEpoch: 1_700_000_000, limit: 5000)
        await stub.setRateLimit(snap, forToken: primaryToken)
        await stub.enqueue(.prs([]), forToken: primaryToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] }
        )

        // Make a call so we hit the primary token (and verify result).
        _ = try await api.listOpenPRs(owner: "acme", repo: "widgets", repoId: repoId)

        let observedPrimary = await api.rateLimit(forAccount: primary)
        XCTAssertEqual(observedPrimary, snap)

        let observedSecondary = await api.rateLimit(forAccount: secondary)
        XCTAssertNil(observedSecondary, "no call yet on secondary's token")

        // Unknown account → nil.
        let observedUnknown = await api.rateLimit(forAccount: UUID())
        XCTAssertNil(observedUnknown)
    }

    // MARK: helpers

    private func makePR(repoId: UUID, number: Int) -> PullRequest {
        PullRequest(
            id: UUID(),
            repoId: repoId,
            number: number,
            title: "PR \(number)",
            authorLogin: "ghost",
            sourceBranch: "feat/x",
            isMine: false,
            state: .open,
            ciState: .success,
            reviewState: .approved,
            labels: [],
            htmlUrl: URL(string: "https://github.com/acme/widgets/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
