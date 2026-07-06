import XCTest
import AppKit
@testable import Aerie

/// Unit coverage for `AvatarStore` — the session-scoped cache behind
/// `AccountAvatar`'s real-GitHub-avatar rendering. The fetch closure is
/// injected so every test is deterministic and offline.
@MainActor
final class AvatarStoreTests: XCTestCase {

    // MARK: - URL construction

    func test_avatarURL_pointsAtGitHubPNGWithSizeParam() {
        XCTAssertEqual(
            AvatarStore.avatarURL(for: "Jarvis-E")?.absoluteString,
            "https://github.com/Jarvis-E.png?size=96"
        )
    }

    func test_avatarURL_percentEncodesLoginsOutsideGitHubAlphabet() {
        XCTAssertEqual(
            AvatarStore.avatarURL(for: "a b/c")?.absoluteString,
            "https://github.com/a%20b%2Fc.png?size=96"
        )
    }

    func test_avatarURL_emptyLoginReturnsNil() {
        XCTAssertNil(AvatarStore.avatarURL(for: ""))
    }

    // MARK: - Fetch + cache behaviour

    func test_image_successfulFetchIsCachedForSubsequentCalls() async {
        let counter = FetchCounter(result: Self.tinyPNG())
        let store = AvatarStore(fetch: counter.fetch)

        let first = await store.image(for: "octocat")
        let second = await store.image(for: "octocat")

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(counter.count, 1, "second lookup must be served from cache")
        XCTAssertNotNil(store.cachedImage(for: "octocat"))
    }

    func test_image_failureIsRememberedWithoutRefetching() async {
        let counter = FetchCounter(result: nil)
        let store = AvatarStore(fetch: counter.fetch)

        let first = await store.image(for: "ghost")
        let second = await store.image(for: "ghost")

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(counter.count, 1, "a failed login must not be re-fetched this session")
        XCTAssertNil(store.cachedImage(for: "ghost"))
    }

    func test_image_undecodableDataCountsAsFailure() async {
        let counter = FetchCounter(result: Data("not a png".utf8))
        let store = AvatarStore(fetch: counter.fetch)

        let image = await store.image(for: "octocat")

        XCTAssertNil(image)
        XCTAssertNil(store.cachedImage(for: "octocat"))
    }

    func test_image_concurrentRequestsShareOneFetch() async {
        let counter = FetchCounter(result: Self.tinyPNG(), delayNanos: 50_000_000)
        let store = AvatarStore(fetch: counter.fetch)

        async let a = store.image(for: "octocat")
        async let b = store.image(for: "octocat")
        let (first, second) = await (a, b)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(counter.count, 1, "overlapping lookups must share one in-flight fetch")
    }

    func test_image_distinctLoginsAreFetchedIndependently() async {
        let counter = FetchCounter(result: Self.tinyPNG())
        let store = AvatarStore(fetch: counter.fetch)

        _ = await store.image(for: "octocat")
        _ = await store.image(for: "Jarvis-E")

        XCTAssertEqual(counter.count, 2)
    }

    // MARK: - Helpers

    /// Thread-safe counting fetch double. `result: nil` simulates a network /
    /// HTTP failure; a delay lets concurrency tests overlap two lookups.
    private final class FetchCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        private let result: Data?
        private let delayNanos: UInt64

        init(result: Data?, delayNanos: UInt64 = 0) {
            self.result = result
            self.delayNanos = delayNanos
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return _count
        }

        func fetch(_ url: URL) async -> Data? {
            lock.lock()
            _count += 1
            lock.unlock()
            if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
            return result
        }
    }

    /// A real 4×4 PNG so the store exercises genuine `NSImage` decoding.
    private static func tinyPNG() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }
}
