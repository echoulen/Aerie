import Foundation
import SwiftGitX

/// Inspects a local folder and produces a `DetectedRepo` summary —
/// owner/repo + host parsed from `origin`, default + current branch,
/// dirty flag, and a suggested account (matched by owner, then host).
///
/// Lives in `Services` because it shells out via `Process`, opens a
/// libgit2 repo, and is the kind of side-effecting glue that doesn't
/// belong in a view model.
///
/// Uses subprocess `git` for the inexpensive reads (config / status /
/// symbolic-ref) instead of SwiftGitX — those calls are well-trodden
/// CLI surface and don't justify the bridging overhead. SwiftGitX is
/// only used to verify the folder is a valid repo at the start.
actor RepoDetector {
    struct DetectionError: Error, Equatable {
        let message: String
    }

    /// Detects metadata about a git repository at `url`. Throws when:
    /// - the folder isn't a git repository (SwiftGitX fails to open)
    /// - `origin` is missing or unparseable as a GitHub-ish URL
    func detect(at url: URL, accounts: [GitHubAccount]) async throws -> DetectedRepo {
        // 1. Verify it's a git repo via SwiftGitX (fully qualified to
        //    avoid colliding with our `Aerie.Repository` model).
        _ = try SwiftGitX.Repository(at: url, createIfNotExists: false)

        // 2. Read origin URL.
        let originRaw = try await runGit(["config", "--get", "remote.origin.url"], in: url)
        let origin = originRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !origin.isEmpty else {
            throw DetectionError(message: "Repository has no `origin` remote.")
        }

        // 3. Parse owner/repo + host.
        guard let parsed = Self.parseGitHubOrigin(origin) else {
            throw DetectionError(message: "Couldn't parse GitHub origin: \(origin)")
        }

        // 4. Default branch via origin/HEAD symbolic-ref, with a `main`
        //    fallback so we always have something to write to the DB.
        let defaultBranch: String = {
            if let raw = try? runGitSync(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: url) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed.replacingOccurrences(of: "origin/", with: "")
                }
            }
            return "main"
        }()

        // 5. Current branch (empty if detached HEAD).
        let currentBranch: String = {
            if let raw = try? runGitSync(["symbolic-ref", "--short", "HEAD"], in: url) {
                return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }()

        // 6. Dirty state via porcelain status (any non-empty output → dirty).
        let statusOutput = (try? runGitSync(["status", "--porcelain"], in: url)) ?? ""
        let isDirty = !statusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // 7. Suggest an account. Prefer the one whose login matches the repo
        //    owner — that's the account that actually owns (and can access)
        //    the repo. Matching on host alone is ambiguous when several
        //    accounts share a host (e.g. multiple github.com logins): it binds
        //    to whichever happened to be first, which may not have access to a
        //    private repo and leaves the PRs/Issues lists silently empty.
        //    Fall back to the first host match for org-owned repos where no
        //    account login equals the owner.
        let suggested =
            accounts.first {
                $0.host == parsed.host
                    && $0.login.caseInsensitiveCompare(parsed.owner) == .orderedSame
            }?.id
            ?? accounts.first { $0.host == parsed.host }?.id

        return DetectedRepo(
            url: url,
            githubOwner: parsed.owner,
            githubRepo: parsed.repo,
            host: parsed.host,
            defaultBranch: defaultBranch,
            currentBranch: currentBranch,
            isDirty: isDirty,
            suggestedAccountId: suggested
        )
    }

    // MARK: - Origin parsing

    /// Parses a git origin URL into (host, owner, repo). Accepts the
    /// SSH form (`git@host:owner/repo[.git]`) and HTTPS form
    /// (`https://host/owner/repo[.git][/]`). Returns nil for anything
    /// else (file://, ssh://, ports, sub-paths, garbage).
    static func parseGitHubOrigin(_ url: String) -> (host: String, owner: String, repo: String)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // SSH form
        if let parsed = regexCapture(
            pattern: #"^git@([^:]+):([^/]+)/([^/]+?)(?:\.git)?$"#,
            in: trimmed
        ) {
            return parsed
        }
        // HTTPS form
        if trimmed.hasPrefix("http") {
            return regexCapture(
                pattern: #"^https?://([^/]+)/([^/]+)/([^/]+?)(?:\.git)?/?$"#,
                in: trimmed
            )
        }
        return nil
    }

    private static func regexCapture(
        pattern: String,
        in s: String
    ) -> (host: String, owner: String, repo: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges == 4,
              let r1 = Range(m.range(at: 1), in: s),
              let r2 = Range(m.range(at: 2), in: s),
              let r3 = Range(m.range(at: 3), in: s)
        else { return nil }
        return (String(s[r1]), String(s[r2]), String(s[r3]))
    }

    // MARK: - git subprocess

    /// Async wrapper around `runGitSync` so the public surface stays
    /// awaitable even though the underlying call is synchronous —
    /// keeps the detector cancellable-by-task without forcing every
    /// call site to bridge into a continuation.
    private func runGit(_ args: [String], in dir: URL) async throws -> String {
        try runGitSync(args, in: dir)
    }

    /// Synchronously runs `git -C <dir> <args>` and returns stdout
    /// when the process exits zero. Throws otherwise — callers either
    /// rescue with `try?` (for the "optional" reads) or propagate.
    private func runGitSync(_ args: [String], in dir: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        // Finder-launched GUI apps inherit only the minimal launchd PATH; add
        // Homebrew dirs so a Homebrew-only `git` still resolves. See SubprocessPATH.
        p.environment = SubprocessPATH.environment()
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        // Drain both pipes concurrently *before* waiting. Reading after
        // `waitUntilExit()` deadlocks once git writes more than the OS pipe
        // buffer (~64 KiB) to a stream nobody is draining — the child blocks on
        // `write()` and never exits. See `SubprocessIO.drainConcurrently`.
        let (outData, errData) = SubprocessIO.drainConcurrently(stdout: stdout, stderr: stderr)
        p.waitUntilExit()
        let out = String(data: outData, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            let errOut = String(data: errData, encoding: .utf8) ?? ""
            throw DetectionError(message: "git \(args.joined(separator: " ")) failed: \(errOut)")
        }
        return out
    }
}
