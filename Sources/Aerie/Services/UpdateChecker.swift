import Foundation

/// A three-segment semantic version (`major.minor.patch`). Tolerates a leading
/// `v` (GitHub tags are `vX.Y.Z`); anything that is not exactly three numeric
/// segments fails to parse and is treated as un-comparable by callers.
struct SemanticVersion: Equatable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else {
            return nil
        }
        (major, minor, patch) = (a, b, c)
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The result of an update check, ready to be rendered as an alert.
enum UpdateOutcome: Equatable {
    case upToDate(current: String)
    case updateAvailable(current: String, latest: String, url: URL)
    case failed(String)
}

/// Abstracts "get the latest release" so the checker can be unit-tested with a
/// stub instead of hitting the network.
protocol ReleaseFetching: Sendable {
    func latestRelease() async throws -> (tag: String, url: URL)
}

enum UpdateCheckError: Error, LocalizedError {
    case http(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .http(let code): return "GitHub returned HTTP \(code)."
        case .malformedResponse: return "The update server response was malformed."
        }
    }
}

/// Default `ReleaseFetching` over the public GitHub Releases API. Anonymous —
/// the repo is public, so no token is needed and account auth is intentionally
/// not pulled in here.
struct GitHubReleaseFetcher: ReleaseFetching {
    var url = URL(string: "https://api.github.com/repos/echoulen/Aerie/releases/latest")!
    var session: URLSession = .shared

    func latestRelease() async throws -> (tag: String, url: URL) {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Aerie", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.malformedResponse }
        guard http.statusCode == 200 else { throw UpdateCheckError.http(http.statusCode) }
        return try Self.parse(data)
    }

    /// Pulls `tag_name` + `html_url` out of the releases/latest payload.
    /// Pure and `static` so it can be unit-tested without networking.
    static func parse(_ data: Data) throws -> (tag: String, url: URL) {
        struct Payload: Decodable { let tag_name: String; let html_url: String }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let url = URL(string: payload.html_url) else { throw UpdateCheckError.malformedResponse }
        return (payload.tag_name, url)
    }
}

/// Compares the running build's version against the latest release.
struct UpdateChecker {
    /// The running build's version. Defaults to the bundle's
    /// `CFBundleShortVersionString` (injected from the git tag at build time).
    var current: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    var fetcher: ReleaseFetching = GitHubReleaseFetcher()

    func check() async -> UpdateOutcome {
        do {
            let (tag, url) = try await fetcher.latestRelease()
            guard let latest = SemanticVersion(tag), let cur = SemanticVersion(current) else {
                return .failed("Couldn't parse version information.")
            }
            if cur < latest {
                return .updateAvailable(current: cur.description, latest: latest.description, url: url)
            }
            return .upToDate(current: cur.description)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
