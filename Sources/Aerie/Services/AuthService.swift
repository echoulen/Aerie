import Foundation

/// Result of bootstrapping authentication via the `gh` CLI.
enum AuthBootstrapResult: Equatable {
    case ok(accounts: [GitHubAccount])
    case ghMissing
    case noAuth
}

/// Errors raised by the mutating account actions (`makePrimary` / `signOut`).
/// These shell out to `gh`, so failures carry the CLI's stderr for surfacing.
enum AuthActionError: Error, LocalizedError {
    case accountNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .accountNotFound: return "Account not found."
        case .commandFailed(let msg): return msg.isEmpty ? "gh command failed." : msg
        }
    }
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
    /// Raw `gh --version` first line, e.g. `"gh version 2.62.0 (2024-01-15)"`.
    /// `nil` until `bootstrap()` has run at least once, or if `gh --version`
    /// failed (which is non-fatal — bootstrap proceeds anyway).
    func ghVersion() -> String?
    /// Scopes parsed from `gh auth status` keyed by the in-memory account id
    /// (which matches the persisted DB id once an `accountStore` is wired).
    func scopesByAccount() -> [UUID: [String]]
    /// First account in the parsed order with `Active account: true`, falling
    /// back to the first parsed account when none is marked active. `nil`
    /// when no accounts were discovered.
    func primaryAccountId() -> UUID?
    /// Makes `accountId` the active gh account via `gh auth switch`. Since
    /// Aerie's "primary" is defined as gh's active account, switching here is
    /// what the Settings → Accounts "Make primary" action does. Callers should
    /// `bootstrap()` afterwards to re-derive the primary id. Throws on a
    /// non-zero gh exit (`AuthActionError`).
    func makePrimary(accountId: UUID) async throws
    /// Signs `accountId` out of gh entirely via `gh auth logout`, removing its
    /// token from the gh keyring so it is no longer rediscovered on the next
    /// bootstrap. Backs the Settings → Accounts "Sign out…" action. Throws on
    /// a non-zero gh exit (`AuthActionError`).
    func signOut(accountId: UUID) async throws
}

// Default implementations let test doubles (`FixedAuthService`,
// `StepAuthService`) keep their minimal signatures — they only ever needed
// `bootstrap()` / `token(for:)` / `allAccounts()`, and the integration-layer
// methods below have well-defined "no data yet" answers.
extension AuthService {
    func ghVersion() -> String? { nil }
    func scopesByAccount() -> [UUID: [String]] { [:] }
    func primaryAccountId() -> UUID? { nil }
    func makePrimary(accountId: UUID) async throws {}
    func signOut(accountId: UUID) async throws {}
}

actor LiveAuthService: AuthService {
    private let runner: SubprocessRunner
    /// Optional persistence layer. When provided, `bootstrap()` upserts the
    /// discovered accounts (matching by `login`+`host`) so downstream views
    /// (`AccountsScreen`, `RepositoriesScreen`) can read them via the DAO.
    /// Reusing existing DB ids keeps token / rate-limit caches stable across
    /// poll cycles. `nil` in tests that don't care about persistence.
    private let accountStore: AccountDAO?
    private var accounts: [GitHubAccount] = []
    private var tokens: [UUID: String] = [:]
    private var scopes: [UUID: [String]] = [:]
    private var primaryId: UUID?
    private var version: String?

    init(runner: SubprocessRunner = LiveSubprocessRunner(), accountStore: AccountDAO? = nil) {
        self.runner = runner
        self.accountStore = accountStore
    }

    func bootstrap() async throws -> AuthBootstrapResult {
        // 1. Detect that `gh` is installed.
        let (whichOut, _, whichRC) = try await runner.run("which", ["gh"])
        let trimmedWhich = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
        if whichRC != 0 || trimmedWhich.isEmpty { return .ghMissing }

        // 2. Capture the CLI version for the Accounts banner. Non-fatal —
        //    older / stripped builds of `gh` may not respond, and that
        //    shouldn't block account discovery.
        if let firstLine = try? await firstLineOfGhVersion(), !firstLine.isEmpty {
            self.version = firstLine
        }

        // 3. Discover accounts via `gh auth status`.
        let (statusOut, _, _) = try await runner.run("gh", ["auth", "status"])
        let parsed = GhAuthStatusParser.parse(stdout: statusOut)
        if parsed.isEmpty {
            // Wipe persisted state too so a user who signed out everywhere
            // doesn't keep seeing stale rows.
            await reconcileStore(with: [])
            self.accounts = []
            self.tokens = [:]
            self.scopes = [:]
            self.primaryId = nil
            return .noAuth
        }

        // 4. Reconcile against the DB (if wired) so each (login,host) keeps
        //    a stable UUID across bootstraps; collect the resulting accounts
        //    in the *parsed* order so `primaryAccountId()` and
        //    `MultiAccountAPI`'s round-robin both see the gh-reported order.
        let resolved = await reconcileStore(with: parsed)

        // 5. Fetch a token for each account and rebuild the scope map.
        var newTokens: [UUID: String] = [:]
        var newScopes: [UUID: [String]] = [:]
        for (i, account) in resolved.enumerated() {
            let p = parsed[i]
            let (tokOut, _, _) = try await runner.run("gh", [
                "auth", "token",
                "--hostname", p.host,
                "--user", p.login,
            ])
            newTokens[account.id] = tokOut.trimmingCharacters(in: .whitespacesAndNewlines)
            newScopes[account.id] = p.scopes
        }

        self.accounts = resolved
        self.tokens = newTokens
        self.scopes = newScopes
        // Primary = first parsed account marked active, falling back to the
        // very first parsed account. Matches gh's own "active account" rule.
        let activeIndex = parsed.firstIndex(where: { $0.active })
        self.primaryId = resolved[activeIndex ?? 0].id

        return .ok(accounts: resolved)
    }

    func token(for accountId: UUID) -> String? { tokens[accountId] }
    func allAccounts() -> [GitHubAccount] { accounts }
    func ghVersion() -> String? { version }
    func scopesByAccount() -> [UUID: [String]] { scopes }
    func primaryAccountId() -> UUID? { primaryId }

    func makePrimary(accountId: UUID) async throws {
        let acc = try account(for: accountId)
        // `--hostname` + `--user` keeps `gh auth switch` non-interactive.
        let (_, err, rc) = try await runner.run("gh", [
            "auth", "switch",
            "--hostname", acc.host,
            "--user", acc.login,
        ])
        if rc != 0 {
            throw AuthActionError.commandFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func signOut(accountId: UUID) async throws {
        let acc = try account(for: accountId)
        // `--hostname` + `--user` makes `gh auth logout` skip its prompt and
        // remove just this account's token.
        let (_, err, rc) = try await runner.run("gh", [
            "auth", "logout",
            "--hostname", acc.host,
            "--user", acc.login,
        ])
        if rc != 0 {
            throw AuthActionError.commandFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Helpers

    /// Resolves an in-memory account by id, throwing `accountNotFound` when the
    /// id is stale (e.g. a card was actioned after the account vanished).
    private func account(for accountId: UUID) throws -> GitHubAccount {
        guard let acc = accounts.first(where: { $0.id == accountId }) else {
            throw AuthActionError.accountNotFound
        }
        return acc
    }

    /// Runs `gh --version` and returns its first stdout line, trimmed. Throws
    /// only on runner errors; returns `nil` on non-zero exit codes or empty
    /// output so callers can degrade gracefully.
    private func firstLineOfGhVersion() async throws -> String? {
        let (out, _, rc) = try await runner.run("gh", ["--version"])
        guard rc == 0 else { return nil }
        let first = out.split(separator: "\n", omittingEmptySubsequences: true).first
        return first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Aligns `accountStore` to match `parsed`:
    ///   - reuses the existing UUID when (login, host) already exists,
    ///   - inserts new rows for unseen (login, host) pairs,
    ///   - deletes rows whose (login, host) is no longer reported by gh.
    /// Returns the resolved `GitHubAccount` list in the same order as `parsed`.
    /// When `accountStore` is `nil` the method just mints fresh UUIDs without
    /// touching any DB.
    @discardableResult
    private func reconcileStore(with parsed: [GhParsedAccount]) async -> [GitHubAccount] {
        guard let store = accountStore else {
            return parsed.map { GitHubAccount(id: UUID(), login: $0.login, host: $0.host) }
        }
        var resolved: [GitHubAccount] = []
        for p in parsed {
            if let existing = try? await store.find(login: p.login, host: p.host) {
                resolved.append(existing)
            } else {
                let acct = GitHubAccount(id: UUID(), login: p.login, host: p.host)
                try? await store.insert(acct)
                resolved.append(acct)
            }
        }
        // Drop accounts that the gh CLI no longer reports.
        if let all = try? await store.all() {
            let kept = Set(resolved.map(\.id))
            for old in all where !kept.contains(old.id) {
                try? await store.delete(id: old.id)
            }
        }
        return resolved
    }
}
