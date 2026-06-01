import Foundation

struct GhParsedAccount: Equatable {
    let host: String
    let login: String
    let scopes: [String]
    let active: Bool
}

enum GhAuthStatusParser {
    /// Parse `gh auth status` stdout into a list of accounts.
    ///
    /// Recognises blocks of the form:
    /// ```
    ///   ✓ Logged in to <host> account <login> (...)
    ///   - Active account: true|false
    ///   - Token scopes: 'scope1', 'scope2'
    /// ```
    /// A block ends on a blank line or on the next "Logged in to" line.
    static func parse(stdout: String) -> [GhParsedAccount] {
        var accounts: [GhParsedAccount] = []

        // In-progress block state.
        var currentHost: String?
        var currentLogin: String?
        var currentScopes: [String] = []
        var currentActive: Bool = false
        var inBlock = false

        func flush() {
            guard inBlock, let host = currentHost, let login = currentLogin else { return }
            accounts.append(GhParsedAccount(
                host: host,
                login: login,
                scopes: currentScopes,
                active: currentActive
            ))
            currentHost = nil
            currentLogin = nil
            currentScopes = []
            currentActive = false
            inBlock = false
        }

        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flush()
                continue
            }

            if let (host, login) = parseLoggedInLine(line) {
                flush()
                currentHost = host
                currentLogin = login
                currentScopes = []
                currentActive = false
                inBlock = true
                continue
            }

            guard inBlock else { continue }

            if let active = parseActiveLine(line) {
                currentActive = active
                continue
            }

            if let scopes = parseScopesLine(line) {
                currentScopes = scopes
                continue
            }
        }

        flush()
        return accounts
    }

    // MARK: - Line parsers

    /// Parses lines of the form `✓ Logged in to <host> account <login> (...)`.
    private static func parseLoggedInLine(_ line: String) -> (host: String, login: String)? {
        guard let range = line.range(of: "Logged in to ") else { return nil }
        let rest = line[range.upperBound...]
        // rest looks like: "github.com account carlos-li (keyring)"
        guard let acctRange = rest.range(of: " account ") else { return nil }
        let host = String(rest[..<acctRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let afterAccount = rest[acctRange.upperBound...]
        // login terminates at first whitespace or '(' from gh's output.
        let login: String
        if let parenIdx = afterAccount.firstIndex(of: "(") {
            login = String(afterAccount[..<parenIdx]).trimmingCharacters(in: .whitespaces)
        } else {
            login = String(afterAccount).trimmingCharacters(in: .whitespaces)
        }
        guard !host.isEmpty, !login.isEmpty else { return nil }
        return (host, login)
    }

    /// Parses `- Active account: true|false`.
    private static func parseActiveLine(_ line: String) -> Bool? {
        guard let range = line.range(of: "Active account:") else { return nil }
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("true") { return true }
        if value.hasPrefix("false") { return false }
        return nil
    }

    /// Parses `- Token scopes: 'a', 'b', 'c'` (quotes may be single or absent).
    private static func parseScopesLine(_ line: String) -> [String]? {
        guard let range = line.range(of: "Token scopes:") else { return nil }
        let rest = line[range.upperBound...]
        let raw = String(rest).trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return [] }
        return raw
            .split(separator: ",")
            .map { piece in
                piece
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }
            .filter { !$0.isEmpty }
    }
}
