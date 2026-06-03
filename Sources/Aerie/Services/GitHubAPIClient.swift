import Foundation

// MARK: - Public supporting types

enum MergeMethod: String, Sendable, Equatable {
    case merge
    case squash
    case rebase
}

struct MergeResult: Sendable, Equatable {
    let sha: String
    let merged: Bool
}

struct RateLimitSnapshot: Sendable, Equatable {
    let remaining: Int
    let resetEpoch: TimeInterval
    let limit: Int
}

struct GitHubAPIError: Error, Equatable, LocalizedError {
    let status: Int
    let message: String

    /// Surfaced verbatim by the merge dialog (`error.localizedDescription`).
    /// Without this `LocalizedError` conformance the NSError bridge yields a
    /// generic "operation couldn't be completed" string and drops `message` —
    /// the only actionable part (e.g. "At least 1 approving review is
    /// required"). The HTTP status is appended as context for real API
    /// failures; synthetic errors (`status == 0`) omit it as noise.
    var errorDescription: String? {
        if message.isEmpty {
            return "GitHub API error (HTTP \(status))"
        }
        return status > 0 ? "\(message) (HTTP \(status))" : message
    }
}

// MARK: - Protocol

/// `GitHubAPIClient` is the thin transport over the GitHub REST + GraphQL APIs.
///
/// Notes on the signature for `listOpenPRs`:
/// - The original plan called `listOpenPRs(owner:repo:token:)`. We deviate here by
///   also accepting `repoId: UUID`. The mapper needs the repo's UUID to populate
///   `PullRequest.repoId`, and pushing that responsibility to the caller (so the
///   caller would otherwise re-map every fetch) duplicates work. This keeps the
///   transport layer aware of the persistence-side identity without inventing it.
protocol GitHubAPIClient: Sendable {
    func listOpenPRs(
        owner: String,
        repo: String,
        repoId: UUID,
        token: String
    ) async throws -> [PullRequest]

    func listOpenIssues(
        owner: String,
        repo: String,
        repoId: UUID,
        token: String
    ) async throws -> [Issue]

    func mergePR(
        owner: String,
        repo: String,
        number: Int,
        method: MergeMethod,
        token: String
    ) async throws -> MergeResult

    /// Fetches a single PR's authoritative merge fields (state,
    /// `mergeStateStatus`, CI rollup, review decision) so a merge can be
    /// re-validated against fresh server state immediately before it fires —
    /// closing the window where a cached row lights the Merge button for a PR
    /// GitHub now refuses. Returns nil when the PR isn't found. Declared on the
    /// protocol (not just the extension) so the live override is dynamically
    /// dispatched through the `GitHubAPIClient` existential in `MultiAccountAPI`.
    func fetchMergeState(
        owner: String,
        repo: String,
        number: Int,
        token: String
    ) async throws -> PullRequest?

    /// Updates the PR's head branch with the latest commits from its base — the
    /// server-side equivalent of GitHub's "Update branch" button (REST `PUT
    /// .../pulls/{number}/update-branch`). Lets Aerie bring a `BEHIND` PR up to
    /// date even when its branch isn't checked out locally, where the local
    /// `git merge` path (`GitService.updateBranchFromBase`) has nothing to run
    /// against. Declared on the protocol — not just the extension — so the live
    /// override is dynamically dispatched through the `GitHubAPIClient`
    /// existential in `MultiAccountAPI`.
    func updatePullRequestBranch(
        owner: String,
        repo: String,
        number: Int,
        token: String
    ) async throws

    /// Returns the most recently observed rate-limit snapshot for the given token,
    /// or nil if we have not yet made a successful request with this token.
    /// Synchronous + nonisolated so it stays cheap on the hot path (the polling
    /// pipeline, settings view, etc).
    func lastRateLimit(token: String) -> RateLimitSnapshot?

    /// Whether `token` can see `owner/repo`. Used by the add-repo flow to bind
    /// an account that can actually reach the repo (an org repo whose owner
    /// doesn't match any account login can't be picked by host/login alone).
    /// Declared on the protocol — not just the extension — so the live override
    /// is dynamically dispatched when called through the `GitHubAPIClient`
    /// existential in `MultiAccountAPI`.
    func repoIsVisible(owner: String, repo: String, token: String) async -> Bool
}

extension GitHubAPIClient {
    /// Default probe: list the repo's open PRs and treat 401/403/404 (the
    /// client maps an invisible private repo to 404) as "not visible". Any
    /// other failure (network, decode) also reads as not-visible so the caller
    /// falls back to its heuristic rather than binding a wrong account.
    /// `LiveGitHubAPIClient` overrides this with a cheap id-only query.
    func repoIsVisible(owner: String, repo: String, token: String) async -> Bool {
        do {
            _ = try await listOpenPRs(owner: owner, repo: repo, repoId: UUID(), token: token)
            return true
        } catch {
            return false
        }
    }

    /// Default: no re-validation data. Conformers that can't query a single PR
    /// (e.g. test stubs that don't opt in) simply skip the pre-merge re-check,
    /// so `MultiAccountAPI.mergePR` falls through to the merge itself.
    func fetchMergeState(
        owner: String,
        repo: String,
        number: Int,
        token: String
    ) async throws -> PullRequest? {
        nil
    }

    /// Default: no-op. Test stubs that don't exercise update-branch inherit a
    /// harmless no-op (mirrors the `fetchMergeState` default); the live client
    /// overrides it with the real REST call.
    func updatePullRequestBranch(
        owner: String,
        repo: String,
        number: Int,
        token: String
    ) async throws {}
}

// MARK: - Rate-limit store (lock-protected, nonisolated read/write)

/// Thin lock-protected map so `lastRateLimit(token:)` can be exposed as a
/// synchronous nonisolated lookup off an actor.
final class RateLimitStore: @unchecked Sendable {
    private var map: [String: RateLimitSnapshot] = [:]
    private let lock = NSLock()

    func get(_ token: String) -> RateLimitSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return map[token]
    }

    func set(_ token: String, _ snap: RateLimitSnapshot) {
        lock.lock(); defer { lock.unlock() }
        map[token] = snap
    }
}

// MARK: - Live implementation

actor LiveGitHubAPIClient: GitHubAPIClient {
    private let session: URLSession
    private let rateLimits = RateLimitStore()

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func lastRateLimit(token: String) -> RateLimitSnapshot? {
        rateLimits.get(token)
    }

    // MARK: listOpenPRs

    private static let listOpenPRsQuery: String = """
    query($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
        pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes {
            id
            number
            title
            author { login }
            headRefName
            state
            mergeable
            mergeStateStatus
            labels(first: 10) { nodes { name } }
            commits(last: 1) {
              nodes {
                commit {
                  statusCheckRollup { state }
                }
              }
            }
            reviewDecision
            reviews(states: [APPROVED], last: 1) { nodes { author { login } } }
            additions
            deletions
            changedFiles
            updatedAt
            url
          }
        }
      }
    }
    """

    func listOpenPRs(
        owner: String,
        repo: String,
        repoId: UUID,
        token: String
    ) async throws -> [PullRequest] {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "query": Self.listOpenPRsQuery,
            "variables": ["owner": owner, "repo": repo],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        recordRateLimit(token: token, response: http)
        try checkOK(status: http?.statusCode ?? 0, data: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ListPRsResponse.self, from: data)
        // GraphQL returns `200 + repository: null` when this token can't see the
        // (private) repo. Surface that as a 404 so `MultiAccountAPI` can fall
        // through to an account that *can* see it, rather than crashing on a
        // non-optional decode.
        guard let repository = decoded.data.repository else {
            throw GitHubAPIError(status: 404, message: "repository not visible")
        }
        return repository.pullRequests.nodes.map { Self.map($0, repoId: repoId) }
    }

    // MARK: listOpenIssues

    // Unlike the REST `/issues` endpoint, the GraphQL `repository.issues`
    // connection NEVER includes pull requests, so there is no PR contamination
    // to filter out. `viewer.login` lets us compute `assignedToMe` against the
    // fetching token's own account.
    private static let listOpenIssuesQuery: String = """
    query($owner: String!, $repo: String!) {
      viewer { login }
      repository(owner: $owner, name: $repo) {
        issues(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes {
            number
            title
            author { login }
            labels(first: 10) { nodes { name color } }
            comments { totalCount }
            assignees(first: 10) { nodes { login } }
            updatedAt
            url
          }
        }
      }
    }
    """

    func listOpenIssues(
        owner: String,
        repo: String,
        repoId: UUID,
        token: String
    ) async throws -> [Issue] {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "query": Self.listOpenIssuesQuery,
            "variables": ["owner": owner, "repo": repo],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        recordRateLimit(token: token, response: http)
        try checkOK(status: http?.statusCode ?? 0, data: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ListIssuesResponse.self, from: data)
        // GraphQL returns `200 + repository: null` when this token can't see the
        // (private) repo. Surface that as a 404 so `MultiAccountAPI` can fall
        // through to an account that *can* see it.
        guard let repository = decoded.data.repository else {
            throw GitHubAPIError(status: 404, message: "repository not visible")
        }
        let viewerLogin = decoded.data.viewer?.login
        return repository.issues.nodes.map {
            Self.map($0, repoId: repoId, viewerLogin: viewerLogin)
        }
    }

    // MARK: repoIsVisible

    private static let repoVisibleQuery: String = """
    query($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) { id }
    }
    """

    /// Cheap visibility probe: ask only for the repo's node id. A non-null
    /// `repository` means this token can see it. Any error (auth, network,
    /// decode) reads as not-visible — the add-repo probe is best-effort and
    /// falls back to its heuristic when it can't confirm.
    func repoIsVisible(owner: String, repo: String, token: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "query": Self.repoVisibleQuery,
            "variables": ["owner": owner, "repo": repo],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = body

        guard let (data, response) = try? await session.data(for: request) else { return false }
        let http = response as? HTTPURLResponse
        recordRateLimit(token: token, response: http)
        guard let status = http?.statusCode, (200...299).contains(status) else { return false }

        struct Resp: Decodable {
            struct DataLayer: Decodable {
                struct Repo: Decodable { let id: String }
                let repository: Repo?
            }
            let data: DataLayer
        }
        guard let decoded = try? JSONDecoder().decode(Resp.self, from: data) else { return false }
        return decoded.data.repository != nil
    }

    // MARK: mergePR

    func mergePR(
        owner: String,
        repo: String,
        number: Int,
        method: MergeMethod,
        token: String
    ) async throws -> MergeResult {
        let urlString =
            "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(number)/merge"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["merge_method": method.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        recordRateLimit(token: token, response: http)
        try checkOK(status: http?.statusCode ?? 0, data: data)

        struct MergeResponse: Decodable {
            let sha: String
            let merged: Bool
        }
        let decoded = try JSONDecoder().decode(MergeResponse.self, from: data)
        return MergeResult(sha: decoded.sha, merged: decoded.merged)
    }

    // MARK: updatePullRequestBranch

    func updatePullRequestBranch(
        owner: String,
        repo: String,
        number: Int,
        token: String
    ) async throws {
        let urlString =
            "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(number)/update-branch"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Empty JSON object body: the optional `expected_head_sha` is omitted so
        // the update always targets the PR's current head. GitHub answers 202
        // Accepted (the merge is queued), which `checkOK` treats as success.
        request.httpBody = try JSONSerialization.data(withJSONObject: [String: Any]())

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        recordRateLimit(token: token, response: http)
        try checkOK(status: http?.statusCode ?? 0, data: data)
    }

    // MARK: fetchMergeState

    // Same node shape as `listOpenPRsQuery` so the existing `map(_:repoId:)`
    // can decode it — just scoped to one PR by number, which is far cheaper
    // than re-listing 50 and lets us re-validate a PR even when it'd fall
    // outside the first page.
    private static let fetchPRQuery: String = """
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          id
          number
          title
          author { login }
          headRefName
          state
          mergeable
          mergeStateStatus
          labels(first: 10) { nodes { name } }
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup { state }
              }
            }
          }
          reviewDecision
          reviews(states: [APPROVED], last: 1) { nodes { author { login } } }
          additions
          deletions
          changedFiles
          updatedAt
          url
        }
      }
    }
    """

    func fetchMergeState(
        owner: String,
        repo: String,
        number: Int,
        token: String
    ) async throws -> PullRequest? {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "query": Self.fetchPRQuery,
            "variables": ["owner": owner, "repo": repo, "number": number] as [String: Any],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        recordRateLimit(token: token, response: http)
        try checkOK(status: http?.statusCode ?? 0, data: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FetchPRResponse.self, from: data)
        // `repository: null` (private repo not visible to this token) or
        // `pullRequest: null` (no such PR) both mean "nothing to re-validate".
        guard let node = decoded.data.repository?.pullRequest else { return nil }
        return Self.map(node, repoId: UUID())
    }

    private struct FetchPRResponse: Decodable {
        struct DataLayer: Decodable { let repository: Repo? }
        struct Repo: Decodable { let pullRequest: ListPRsResponse.Node? }
        let data: DataLayer
    }

    // MARK: Helpers

    private func checkOK(status: Int, data: Data) throws {
        guard !(200...299).contains(status) else { return }
        // Best-effort message extraction.
        var message = ""
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = obj["message"] as? String {
            message = m
        }
        throw GitHubAPIError(status: status, message: message)
    }

    private func recordRateLimit(token: String, response: HTTPURLResponse?) {
        guard let response else { return }
        // HTTPURLResponse header lookup is case-insensitive on Apple platforms,
        // but the canonical keys GitHub uses are lowercased.
        func header(_ key: String) -> String? {
            response.value(forHTTPHeaderField: key)
        }
        guard
            let remainingStr = header("x-ratelimit-remaining"),
            let resetStr = header("x-ratelimit-reset"),
            let limitStr = header("x-ratelimit-limit"),
            let remaining = Int(remainingStr),
            let reset = TimeInterval(resetStr),
            let limit = Int(limitStr)
        else { return }
        rateLimits.set(
            token,
            RateLimitSnapshot(remaining: remaining, resetEpoch: reset, limit: limit)
        )
    }

    // MARK: GraphQL DTO + mapping

    private struct ListPRsResponse: Decodable {
        struct DataLayer: Decodable { let repository: Repo? }
        struct Repo: Decodable { let pullRequests: PRsLayer }
        struct PRsLayer: Decodable { let nodes: [Node] }
        struct Node: Decodable {
            let id: String
            let number: Int
            let title: String
            let author: Author?
            let headRefName: String
            let state: String
            let mergeable: String
            let mergeStateStatus: String?
            let labels: LabelLayer
            let commits: CommitsLayer
            let reviewDecision: String?
            let reviews: ReviewsLayer?
            let additions: Int?
            let deletions: Int?
            let changedFiles: Int?
            let updatedAt: Date
            let url: URL
        }
        struct Author: Decodable { let login: String }
        struct LabelLayer: Decodable { let nodes: [LabelNode] }
        struct LabelNode: Decodable { let name: String }
        struct CommitsLayer: Decodable { let nodes: [CommitNode] }
        struct CommitNode: Decodable { let commit: CommitInner }
        struct CommitInner: Decodable { let statusCheckRollup: RollupOrNull? }
        struct RollupOrNull: Decodable { let state: String }
        struct ReviewsLayer: Decodable { let nodes: [ReviewNode] }
        struct ReviewNode: Decodable { let author: Author? }
        let data: DataLayer
    }

    private static func map(_ node: ListPRsResponse.Node, repoId: UUID) -> PullRequest {
        let state: PRState
        switch node.state {
        case "OPEN": state = .open
        case "CLOSED": state = .closed
        case "MERGED": state = .merged
        default: state = .open
        }

        let ci: CIState
        switch node.commits.nodes.first?.commit.statusCheckRollup?.state {
        case "SUCCESS": ci = .success
        case "FAILURE", "ERROR": ci = .failure
        case "PENDING", "EXPECTED": ci = .pending
        default: ci = .none
        }

        let review: ReviewState
        switch node.reviewDecision {
        case "APPROVED": review = .approved
        case "CHANGES_REQUESTED": review = .changesRequested
        default: review = .reviewRequired
        }

        return PullRequest(
            id: UUID(),
            repoId: repoId,
            number: node.number,
            title: node.title,
            authorLogin: node.author?.login ?? "",
            sourceBranch: node.headRefName,
            isMine: false,
            state: state,
            ciState: ci,
            reviewState: review,
            labels: node.labels.nodes.map(\.name),
            htmlUrl: node.url,
            updatedAt: node.updatedAt,
            approvedBy: node.reviews?.nodes.first?.author?.login,
            additions: node.additions,
            deletions: node.deletions,
            changedFiles: node.changedFiles,
            mergeStateStatus: node.mergeStateStatus
        )
    }

    // MARK: Issues GraphQL DTO + mapping

    private struct ListIssuesResponse: Decodable {
        struct DataLayer: Decodable {
            let viewer: Viewer?
            let repository: Repo?
        }
        struct Viewer: Decodable { let login: String }
        struct Repo: Decodable { let issues: IssuesLayer }
        struct IssuesLayer: Decodable { let nodes: [Node] }
        struct Node: Decodable {
            let number: Int
            let title: String
            let author: Author?
            let labels: LabelLayer
            let comments: CommentsLayer
            let assignees: AssigneesLayer
            let updatedAt: Date
            let url: URL
        }
        struct Author: Decodable { let login: String }
        struct LabelLayer: Decodable { let nodes: [LabelNode] }
        struct LabelNode: Decodable { let name: String; let color: String }
        struct CommentsLayer: Decodable { let totalCount: Int }
        struct AssigneesLayer: Decodable { let nodes: [Assignee] }
        struct Assignee: Decodable { let login: String }
        let data: DataLayer
    }

    private static func map(
        _ node: ListIssuesResponse.Node,
        repoId: UUID,
        viewerLogin: String?
    ) -> Issue {
        let assignees = node.assignees.nodes.map(\.login)
        // Provisional, single-account default — `IssueSyncService` re-resolves
        // this against *all* connected accounts once it has the full set.
        let assignedToMe: Bool
        if let viewerLogin {
            assignedToMe = assignees.contains(viewerLogin)
        } else {
            assignedToMe = false
        }
        return Issue(
            id: UUID(),
            repoId: repoId,
            number: node.number,
            title: node.title,
            authorLogin: node.author?.login ?? "",
            assignedToMe: assignedToMe,
            assigneeLogins: assignees,
            labels: node.labels.nodes.map { IssueLabel(name: $0.name, color: $0.color) },
            commentCount: node.comments.totalCount,
            htmlUrl: node.url,
            updatedAt: node.updatedAt
        )
    }
}
