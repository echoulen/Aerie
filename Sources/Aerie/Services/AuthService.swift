import Foundation

/// Result of bootstrapping authentication via the `gh` CLI.
enum AuthBootstrapResult: Equatable {
    case ok(accounts: [GitHubAccount])
    case ghMissing
    case noAuth
}

/// AuthService discovers GitHub accounts via the `gh` CLI and caches their tokens
/// in-memory for the lifetime of the actor.
///
/// Note: the protocol's `token(for:)` and `allAccounts()` are synchronous getters
/// (not `async throws`) — they are nominally synchronous methods on an actor, which
/// callers still await due to actor isolation. This intentionally narrows the
/// signature compared to the original plan to match `LiveAuthService`'s concrete
/// methods.
protocol AuthService: Actor {
    func bootstrap() async throws -> AuthBootstrapResult
    func token(for accountId: UUID) -> String?
    func allAccounts() -> [GitHubAccount]
}

actor LiveAuthService: AuthService {
    private let runner: SubprocessRunner
    private var accounts: [GitHubAccount] = []
    private var tokens: [UUID: String] = [:]

    init(runner: SubprocessRunner = LiveSubprocessRunner()) {
        self.runner = runner
    }

    func bootstrap() async throws -> AuthBootstrapResult {
        // 1. Detect that `gh` is installed.
        let (whichOut, _, whichRC) = try await runner.run("which", ["gh"])
        let trimmedWhich = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
        if whichRC != 0 || trimmedWhich.isEmpty { return .ghMissing }

        // 2. Discover accounts via `gh auth status`.
        let (statusOut, _, _) = try await runner.run("gh", ["auth", "status"])
        let parsed = GhAuthStatusParser.parse(stdout: statusOut)
        if parsed.isEmpty { return .noAuth }

        // 3. Fetch a token for each parsed account.
        var accs: [GitHubAccount] = []
        var toks: [UUID: String] = [:]
        for p in parsed {
            let acct = GitHubAccount(id: UUID(), login: p.login, host: p.host)
            let (tokOut, _, _) = try await runner.run("gh", [
                "auth", "token",
                "--hostname", p.host,
                "--user", p.login,
            ])
            toks[acct.id] = tokOut.trimmingCharacters(in: .whitespacesAndNewlines)
            accs.append(acct)
        }

        self.accounts = accs
        self.tokens = toks
        return .ok(accounts: accs)
    }

    func token(for accountId: UUID) -> String? { tokens[accountId] }
    func allAccounts() -> [GitHubAccount] { accounts }
}
