import XCTest
@testable import Aerie

// MARK: - Mock GitHubAPIClient

/// In-memory client that returns canned results keyed by token. Lets us
/// exercise `MultiAccountAPI`'s fallback logic without driving URLSession.
actor StubGitHubAPIClient: GitHubAPIClient {
    enum Outcome {
        case prs([PullRequest])
        case issues([Issue])
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
        case .issues, .merge:
            throw GitHubAPIError(status: -1, message: "wrong outcome type for listOpenPRs")
        }
    }

    func listOpenIssues(
        owner: String,
        repo: String,
        repoId: UUID,
        token: String
    ) async throws -> [Issue] {
        let outcome = try consume(token: token)
        switch outcome {
        case .issues(let issues): return issues
        case .apiError(let err): throw err
        case .throwError(let err): throw err
        case .prs, .merge:
            throw GitHubAPIError(status: -1, message: "wrong outcome type for listOpenIssues")
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
        case .prs, .issues:
            throw GitHubAPIError(status: -1, message: "wrong outcome type for mergePR")
        }
    }

    nonisolated func lastRateLimit(token: String) -> RateLimitSnapshot? {
        rateLimits.get(token)
    }

    /// Fresh PR returned by `fetchMergeState`, keyed by token. Absent ⇒ nil,
    /// matching the protocol default — so tests that don't opt in keep their
    /// existing merge behaviour (no pre-merge re-validation data available).
    /// Read without touching `callCount`/`tokensUsed`, so those still count
    /// only the merge PUT itself.
    var freshPRByToken: [String: PullRequest] = [:]

    func setFreshPR(_ pr: PullRequest, forToken token: String) {
        freshPRByToken[token] = pr
    }

    func fetchMergeState(
        owner: String,
        repo: String,
        number: Int,
        token: String
    ) async throws -> PullRequest? {
        freshPRByToken[token]
    }

    // MARK: Approve recording

    /// Tokens an approve was attempted with, in order, plus the comment body.
    private(set) var approveCalls: [(token: String, body: String?)] = []
    /// Per-token error to throw from `approvePR` (e.g. simulate a 403).
    var approveErrorByToken: [String: GitHubAPIError] = [:]

    func setApproveError(_ err: GitHubAPIError, forToken token: String) {
        approveErrorByToken[token] = err
    }

    func approvePR(
        owner: String,
        repo: String,
        number: Int,
        body: String?,
        token: String
    ) async throws {
        approveCalls.append((token, body))
        if let err = approveErrorByToken[token] { throw err }
    }

    // MARK: PR files (review screen / get_pr_diff)
    var prFilesByToken: [String: [PRFileChange]] = [:]
    var prFilesErrorByToken: [String: GitHubAPIError] = [:]
    func setPRFiles(_ files: [PRFileChange], forToken token: String) { prFilesByToken[token] = files }
    func setPRFilesError(_ err: GitHubAPIError, forToken token: String) { prFilesErrorByToken[token] = err }
    func fetchPRFiles(owner: String, repo: String, number: Int, token: String) async throws -> [PRFileChange] {
        if let err = prFilesErrorByToken[token] { throw err }
        return prFilesByToken[token] ?? []
    }

    // MARK: Update branch (server-side)
    private(set) var updateBranchCalls: [String] = []
    var updateBranchErrorByToken: [String: GitHubAPIError] = [:]
    func setUpdateBranchError(_ err: GitHubAPIError, forToken token: String) { updateBranchErrorByToken[token] = err }
    func updatePullRequestBranch(owner: String, repo: String, number: Int, token: String) async throws {
        updateBranchCalls.append(token)
        if let err = updateBranchErrorByToken[token] { throw err }
    }

    func mergedPR(
        owner: String,
        repo: String,
        headBranch: String,
        token: String
    ) async throws -> MergedPRRef? {
        nil
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

    func test_listOpenPRs_fallsBackOn404_repoNotVisibleToFirstAccount() async throws {
        // A private repo the first account can't see returns HTTP 200 +
        // `repository: null`, which the client surfaces as a 404. The fallback
        // must advance to an account that *can* see it.
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "cant_see"
        let secondaryToken = "can_see"
        let repoId = UUID()
        let pr = makePR(repoId: repoId, number: 9)

        let stub = StubGitHubAPIClient()
        await stub.enqueue(
            .apiError(GitHubAPIError(status: 404, message: "repository not visible")),
            forToken: primaryToken
        )
        await stub.enqueue(.prs([pr]), forToken: secondaryToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] }
        )

        let result = try await api.listOpenPRs(owner: "acme", repo: "secret", repoId: repoId)
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

    // MARK: listOpenPRs(forAccount:) — single, repo-bound account

    func test_listOpenPRs_forAccount_usesOnlyThatAccountsToken() async throws {
        // Targeting a specific account must use exactly that account's token,
        // never the round-robin order (the orchestrator passes the repo's bound
        // `primaryAccountId`, which is precise and sidesteps the fallback path).
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "primary_tok"
        let secondaryToken = "secondary_tok"
        let repoId = UUID()
        let pr = makePR(repoId: repoId, number: 5)

        let stub = StubGitHubAPIClient()
        await stub.enqueue(.prs([pr]), forToken: secondaryToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] }
        )

        let result = try await api.listOpenPRs(
            owner: "acme",
            repo: "widgets",
            repoId: repoId,
            accountId: secondary
        )

        XCTAssertEqual(result.value, [pr])
        XCTAssertEqual(result.successfulAccountId, secondary)
        let tokensUsed = await stub.tokensUsed
        XCTAssertEqual(tokensUsed, [secondaryToken], "must not touch the primary token")
    }

    func test_listOpenPRs_forAccount_doesNotFallBackOnAuthError() async throws {
        // A single-account fetch never advances to another account — even on a
        // 401 the error propagates so the caller can surface/log it.
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "bad_tok"
        let secondaryToken = "good_tok"

        let stub = StubGitHubAPIClient()
        await stub.enqueue(
            .apiError(GitHubAPIError(status: 401, message: "Bad credentials")),
            forToken: primaryToken
        )
        // Secondary would succeed if we (wrongly) fell back.
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
                repoId: UUID(),
                accountId: primary
            )
            XCTFail("expected throw")
        } catch let error as GitHubAPIError {
            XCTAssertEqual(error.status, 401)
        }

        let count = await stub.callCount
        XCTAssertEqual(count, 1, "single-account fetch must not fall back")
    }

    func test_listOpenPRs_forAccount_recordsLastUsedForThatAccountOnly() async throws {
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "primary_tok"
        let secondaryToken = "secondary_tok"
        let repoId = UUID()

        let stub = StubGitHubAPIClient()
        await stub.enqueue(.prs([]), forToken: secondaryToken)

        let fixed = Date(timeIntervalSince1970: 1_700_009_999)
        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] },
            now: { fixed }
        )

        _ = try await api.listOpenPRs(owner: "acme", repo: "widgets", repoId: repoId, accountId: secondary)

        let secondaryRecord = await api.lastUsed(forAccount: secondary)
        XCTAssertEqual(secondaryRecord, fixed)
        let primaryRecord = await api.lastUsed(forAccount: primary)
        XCTAssertNil(primaryRecord, "the untargeted account is never recorded")
    }

    func test_listOpenPRs_forAccount_throwsWhenAccountHasNoToken() async throws {
        let known = UUID()
        let unknown = UUID()
        let stub = StubGitHubAPIClient()

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [known: "tok"] },
            accountsInOrder: { [known] }
        )

        do {
            _ = try await api.listOpenPRs(
                owner: "acme",
                repo: "widgets",
                repoId: UUID(),
                accountId: unknown
            )
            XCTFail("expected throw")
        } catch is GitHubAPIError {
            // expected — no token for the requested account
        }
        let count = await stub.callCount
        XCTAssertEqual(count, 0, "no token → no network call")
    }

    // MARK: resolveAccount — probe which account can see a repo

    func test_resolveAccount_returnsFirstAccountThatCanSeeRepo() async throws {
        // The first account can't see the (private org) repo — GraphQL surfaces
        // that as a 404 — so the probe must advance to the account that can.
        let first = UUID()
        let second = UUID()
        let firstToken = "cant_see"
        let secondToken = "can_see"

        let stub = StubGitHubAPIClient()
        await stub.enqueue(.apiError(GitHubAPIError(status: 404, message: "repository not visible")), forToken: firstToken)
        await stub.enqueue(.prs([]), forToken: secondToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [first: firstToken, second: secondToken] },
            accountsInOrder: { [first, second] }
        )

        let resolved = await api.resolveAccount(owner: "acme-co", repo: "web-portal")
        XCTAssertEqual(resolved, second)
        let tokensUsed = await stub.tokensUsed
        XCTAssertEqual(tokensUsed, [firstToken, secondToken])
    }

    func test_resolveAccount_stopsAtFirstVisibleAccount() async throws {
        // The first account can see it → no need to probe the rest.
        let first = UUID()
        let second = UUID()
        let firstToken = "can_see"
        let secondToken = "unused"

        let stub = StubGitHubAPIClient()
        await stub.enqueue(.prs([]), forToken: firstToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [first: firstToken, second: secondToken] },
            accountsInOrder: { [first, second] }
        )

        let resolved = await api.resolveAccount(owner: "acme", repo: "widgets")
        XCTAssertEqual(resolved, first)
        let count = await stub.callCount
        XCTAssertEqual(count, 1, "should stop probing once an account can see the repo")
    }

    func test_resolveAccount_returnsNilWhenNoAccountCanSee() async throws {
        let first = UUID()
        let second = UUID()
        let firstToken = "no1"
        let secondToken = "no2"

        let stub = StubGitHubAPIClient()
        await stub.enqueue(.apiError(GitHubAPIError(status: 404, message: "nope")), forToken: firstToken)
        await stub.enqueue(.apiError(GitHubAPIError(status: 404, message: "nope")), forToken: secondToken)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [first: firstToken, second: secondToken] },
            accountsInOrder: { [first, second] }
        )

        let resolved = await api.resolveAccount(owner: "acme", repo: "secret")
        XCTAssertNil(resolved)
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

    // MARK: lastUsed

    func test_lastUsed_recordsTimestampOnSuccess() async throws {
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "primary_tok"
        let secondaryToken = "secondary_tok"
        let repoId = UUID()

        let stub = StubGitHubAPIClient()
        await stub.enqueue(.prs([]), forToken: primaryToken)

        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] },
            now: { fixed }
        )

        // Before any call → nil for every account.
        let beforePrimary = await api.lastUsed(forAccount: primary)
        XCTAssertNil(beforePrimary)
        let beforeSecondary = await api.lastUsed(forAccount: secondary)
        XCTAssertNil(beforeSecondary)

        _ = try await api.listOpenPRs(owner: "acme", repo: "widgets", repoId: repoId)

        // Primary was used → records the injected `now`.
        let afterPrimary = await api.lastUsed(forAccount: primary)
        XCTAssertEqual(afterPrimary, fixed)
        // Secondary was never tried → still nil.
        let afterSecondary = await api.lastUsed(forAccount: secondary)
        XCTAssertNil(afterSecondary)
    }

    func test_lastUsed_recordsTimestampForFallbackAccount() async throws {
        let primary = UUID()
        let secondary = UUID()
        let primaryToken = "bad_tok"
        let secondaryToken = "good_tok"
        let repoId = UUID()

        let stub = StubGitHubAPIClient()
        await stub.enqueue(
            .apiError(GitHubAPIError(status: 401, message: "Bad credentials")),
            forToken: primaryToken
        )
        await stub.enqueue(.prs([]), forToken: secondaryToken)

        let fixed = Date(timeIntervalSince1970: 1_700_005_555)
        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: primaryToken, secondary: secondaryToken] },
            accountsInOrder: { [primary, secondary] },
            now: { fixed }
        )

        _ = try await api.listOpenPRs(owner: "acme", repo: "widgets", repoId: repoId)

        // Primary failed → no record. Secondary succeeded → record.
        let primaryRecord = await api.lastUsed(forAccount: primary)
        XCTAssertNil(primaryRecord)
        let secondaryRecord = await api.lastUsed(forAccount: secondary)
        XCTAssertEqual(secondaryRecord, fixed)
    }

    // MARK: mergePR — pre-merge re-validation against fresh server state
    //
    // The reported bug: the Merge button lights up off a *cached* row, but by
    // the time the user clicks, GitHub's authoritative state has flipped to
    // BLOCKED (e.g. a required review appeared). `mergePR` re-checks the live
    // state with the same token first, and refuses (with a clear reason) rather
    // than firing a PUT GitHub will reject.

    func test_mergePR_refusesWhenFreshStateNoLongerMergeable() async throws {
        let primary = UUID()
        let token = "tok"
        let stub = StubGitHubAPIClient()
        // Fresh server state says the PR is now BLOCKED.
        await stub.setFreshPR(
            makePR(repoId: UUID(), number: 796, mergeStateStatus: "BLOCKED"),
            forToken: token
        )
        // A merge result is queued, but must never be consumed.
        await stub.enqueue(.merge(MergeResult(sha: "x", merged: true)), forToken: token)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: token] },
            accountsInOrder: { [primary] }
        )

        do {
            _ = try await api.mergePR(owner: "acme", repo: "widgets", number: 796, method: .squash)
            XCTFail("expected the stale-cache merge to be refused")
        } catch let error as GitHubAPIError {
            XCTAssertFalse(error.message.isEmpty, "the refusal must explain why")
        }

        let count = await stub.callCount
        XCTAssertEqual(count, 0, "must not issue the merge PUT when fresh state says it's blocked")
    }

    func test_mergePR_proceedsWhenFreshStateMergeable() async throws {
        let primary = UUID()
        let token = "tok"
        let stub = StubGitHubAPIClient()
        await stub.setFreshPR(
            makePR(repoId: UUID(), number: 5, mergeStateStatus: "CLEAN"),
            forToken: token
        )
        await stub.enqueue(.merge(MergeResult(sha: "abc", merged: true)), forToken: token)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: token] },
            accountsInOrder: { [primary] }
        )

        let result = try await api.mergePR(owner: "acme", repo: "widgets", number: 5, method: .squash)
        XCTAssertTrue(result.value.merged)
        let count = await stub.callCount
        XCTAssertEqual(count, 1, "the merge PUT runs once when fresh state is mergeable")
    }

    func test_mergePR_proceedsWhenNoFreshStateAvailable() async throws {
        // Back-compat / resilience: when re-validation yields nothing (PR not
        // found, or the re-check query couldn't run), fall through to the merge
        // rather than blocking the user on an inability to validate.
        let primary = UUID()
        let token = "tok"
        let stub = StubGitHubAPIClient()
        await stub.enqueue(.merge(MergeResult(sha: "abc", merged: true)), forToken: token)

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: token] },
            accountsInOrder: { [primary] }
        )

        let result = try await api.mergePR(owner: "acme", repo: "widgets", number: 5, method: .squash)
        XCTAssertTrue(result.value.merged)
    }

    func test_mergePR_treatsAlreadyMergedAsIdempotentSuccess() async throws {
        // Auto-merge (or another client) landed the merge after the button lit
        // off a cached row. The re-validation sees state == .merged and returns
        // success WITHOUT firing the merge PUT, so the user sees the PR drop off
        // rather than a confusing "Merge failed … the pull request is merged".
        let primary = UUID()
        let token = "tok"
        let repoId = UUID()
        let mergedPR = PullRequest(
            id: UUID(), repoId: repoId, number: 9, title: "PR 9", authorLogin: "ghost",
            sourceBranch: "feat/x", isMine: false, state: .merged, ciState: .success,
            reviewState: .approved, labels: [],
            htmlUrl: URL(string: "https://github.com/acme/widgets/pull/9")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let stub = StubGitHubAPIClient()
        await stub.setFreshPR(mergedPR, forToken: token)
        // Intentionally enqueue NO merge outcome: if the code wrongly fires the
        // PUT, the stub throws "no canned outcome" and the test fails.

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [primary: token] },
            accountsInOrder: { [primary] }
        )

        let result = try await api.mergePR(owner: "acme", repo: "widgets", number: 9, method: .squash)
        XCTAssertTrue(result.value.merged)
        let count = await stub.callCount
        XCTAssertEqual(count, 0, "an already-merged PR must not fire the merge PUT")
    }

    // MARK: approvePR

    func test_approvePR_usesExactlyTheChosenAccount() async throws {
        let approver = UUID()
        let other = UUID()
        let approverToken = "approver_tok"
        let otherToken = "other_tok"
        let stub = StubGitHubAPIClient()

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [approver: approverToken, other: otherToken] },
            accountsInOrder: { [other, approver] } // 'other' is first in order…
        )

        let result = try await api.approvePR(
            owner: "acme", repo: "widgets", number: 7,
            body: "LGTM", accountId: approver // …but we picked 'approver' explicitly
        )
        XCTAssertEqual(result.successfulAccountId, approver)
        let calls = await stub.approveCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.token, approverToken)
        XCTAssertEqual(calls.first?.body, "LGTM")
    }

    func test_stub_fetchPRFiles_returnsQueuedFiles() async throws {
        let stub = StubGitHubAPIClient()
        let file = PRFileChange(filename: "a.swift", status: .modified, additions: 1, deletions: 0, patch: "@@")
        await stub.setPRFiles([file], forToken: "tok")
        let out = try await stub.fetchPRFiles(owner: "o", repo: "r", number: 1, token: "tok")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.filename, "a.swift")
    }

    func test_approvePR_doesNotFallBackOnError() async throws {
        let approver = UUID()
        let other = UUID()
        let approverToken = "approver_tok"
        let otherToken = "other_tok"
        let stub = StubGitHubAPIClient()
        await stub.setApproveError(
            GitHubAPIError(status: 403, message: "Can not approve your own pull request"),
            forToken: approverToken
        )

        let api = MultiAccountAPI(
            client: stub,
            tokensByAccount: { [approver: approverToken, other: otherToken] },
            accountsInOrder: { [approver, other] }
        )

        do {
            _ = try await api.approvePR(
                owner: "acme", repo: "widgets", number: 7, body: nil, accountId: approver)
            XCTFail("expected approvePR to throw")
        } catch let err as GitHubAPIError {
            XCTAssertEqual(err.status, 403)
        }
        // Only the chosen account was tried — no round-robin to 'other'.
        let calls = await stub.approveCalls
        XCTAssertEqual(calls.map(\.token), [approverToken])
    }

    // MARK: helpers

    private func makePR(repoId: UUID, number: Int, mergeStateStatus: String? = nil) -> PullRequest {
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
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            mergeStateStatus: mergeStateStatus
        )
    }
}
