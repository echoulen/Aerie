import AppKit

/// Session-scoped cache of real GitHub avatars for `AccountAvatar`.
///
/// Fetches `https://github.com/<login>.png` — GitHub's public avatar
/// redirect — so no API call, token, or rate-limit bookkeeping is involved.
/// Results are kept in memory for the life of the process:
/// - a decoded image is cached and never re-fetched;
/// - a failure (offline, 404 for GHE-only logins, undecodable body) is
///   remembered so the login isn't hammered every time a menu re-opens —
///   the view simply keeps its initials fallback until next launch;
/// - overlapping lookups for the same login (titlebar pill + dropdown panel
///   render together) share a single in-flight fetch.
///
/// `@MainActor` because every caller is a SwiftUI view and the cache is
/// plain dictionary state; the network wait itself happens off-actor inside
/// `URLSession`.
@MainActor
final class AvatarStore {
    static let shared = AvatarStore()

    /// Pixel size requested from GitHub. The largest render is the 44 pt
    /// Settings account card — 88 px at 2×, so 96 covers every call site.
    static let fetchPixelSize = 96

    private var images: [String: NSImage] = [:]
    private var unavailable: Set<String> = []
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    private let fetch: @Sendable (URL) async -> Data?

    init(fetch: @escaping @Sendable (URL) async -> Data? = AvatarStore.httpFetch) {
        self.fetch = fetch
    }

    /// `https://github.com/<login>.png?size=96`, or nil for an empty login.
    /// GitHub logins are `[A-Za-z0-9-]`, but anything outside a conservative
    /// URL alphabet is percent-encoded so a malformed login can't smuggle
    /// path segments into the request.
    static func avatarURL(for login: String) -> URL? {
        guard !login.isEmpty,
              let escaped = login.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
              )
        else { return nil }
        return URL(string: "https://github.com/\(escaped).png?size=\(fetchPixelSize)")
    }

    /// Synchronous cache read — lets views render an already-fetched avatar
    /// on their very first frame, without waiting for a `.task` to fire.
    func cachedImage(for login: String) -> NSImage? {
        images[login]
    }

    /// The avatar for `login`, fetching it on first use. Returns nil when the
    /// avatar can't be fetched or decoded (callers keep their fallback).
    func image(for login: String) async -> NSImage? {
        if let image = images[login] { return image }
        if unavailable.contains(login) { return nil }
        if let task = inflight[login] { return await task.value }
        guard let url = Self.avatarURL(for: login) else {
            unavailable.insert(login)
            return nil
        }

        let task = Task<NSImage?, Never> { [fetch] in
            guard let data = await fetch(url), let image = NSImage(data: data) else { return nil }
            return image
        }
        inflight[login] = task
        let image = await task.value
        inflight[login] = nil
        if let image {
            images[login] = image
        } else {
            unavailable.insert(login)
        }
        return image
    }

    // nonisolated: referenced as `init`'s default argument, which evaluates
    // outside the main actor.
    private nonisolated static let httpFetch: @Sendable (URL) async -> Data? = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty
        else { return nil }
        return data
    }
}
