import Foundation
import CoreServices

// Gates the per-tick git status read. libgit2's status walk is O(files in the
// working tree) with no untracked cache — a UE project whose .gitignore matches
// 52k files one by one cost ~8 s per walk, and the poller walked it every
// 30 s. Two gates, both cheap:
//
//   1. `WorkingTreeChangeSource` — has anything under the tree changed since
//      the last read? FSEvents answers that for free; an idle fleet reads
//      nothing.
//   2. `StatusReadPolicy` — a repo whose last read was slow only re-reads on
//      the long cadence, so an editor that keeps writing into an ignored
//      directory can't turn gate 1 back into a walk per tick.

// MARK: - Change source

/// Answers "did this working tree change since I last asked?". Implementations
/// must be safe to call from any thread.
protocol WorkingTreeChangeSource: Sendable {
    /// Reports whether `url`'s tree changed since the previous call for it, and
    /// clears that state. A tree never asked about before always reports true.
    func consumeChange(at url: URL) -> Bool
    /// Makes every tree report a change on its next `consumeChange` — the
    /// manual Refresh button must always re-read.
    func markAllChanged()
}

/// Every call reports a change: the pre-gating behaviour, for tests and call
/// sites that have no watcher.
struct AlwaysChanged: WorkingTreeChangeSource {
    func consumeChange(at url: URL) -> Bool { true }
    func markAllChanged() {}
}

/// FSEvents-backed change source. One stream per watched root, started lazily
/// on the first `consumeChange` for that root; events just flip a per-root
/// flag that the next `consumeChange` reads and clears.
///
/// Directory-level events (no `kFSEventStreamCreateFlagFileEvents`) are enough:
/// we only need "something under here changed", and they're far cheaper for
/// the kernel to coalesce. Deliberately no `IgnoreSelf`: Aerie's own writes
/// into a repo (`.claude/.mcp.json`) change its status too, and our libgit2
/// reads never write, so there's nothing of ours to filter out.
final class WorkingTreeWatcher: WorkingTreeChangeSource, @unchecked Sendable {
    /// Retained per root so the C callback's `info` pointer stays valid for the
    /// stream's whole life. Unowned back-reference: the watcher owns the boxes
    /// and tears every stream down in `deinit`.
    private final class Stream {
        unowned let watcher: WorkingTreeWatcher
        let key: String
        var ref: FSEventStreamRef?
        init(watcher: WorkingTreeWatcher, key: String) { self.watcher = watcher; self.key = key }
    }

    private let lock = NSLock()
    private var streams: [String: Stream] = [:]
    private var changed: [String: Bool] = [:]
    private let queue = DispatchQueue(label: "dev.echoulen.Aerie.WorkingTreeWatcher")
    /// Seconds FSEvents may coalesce before delivering. The poller only asks
    /// every 30 s, so a second of slack costs nothing and cuts wakeups.
    private let latency: CFTimeInterval = 1

    init() {}

    deinit { stopAll() }

    func consumeChange(at url: URL) -> Bool {
        let key = Self.key(url)
        lock.lock(); defer { lock.unlock() }
        if streams[key] == nil {
            start(key: key)
            // First read is happening now — nothing to report until an event.
            changed[key] = false
            return true
        }
        let was = changed[key] ?? false
        changed[key] = false
        return was
    }

    func markAllChanged() {
        lock.lock(); defer { lock.unlock() }
        for key in streams.keys { changed[key] = true }
    }

    /// Stops and releases every stream. Called from `deinit`; tests call it
    /// explicitly so temp directories can be removed cleanly.
    func stopAll() {
        lock.lock(); defer { lock.unlock() }
        for stream in streams.values { stop(stream) }
        streams.removeAll()
        changed.removeAll()
    }

    // MARK: Internals (call with `lock` held)

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func start(key: String) {
        let stream = Stream(watcher: self, key: key)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(stream).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let stream = Unmanaged<Stream>.fromOpaque(info).takeUnretainedValue()
            stream.watcher.noteChange(key: stream.key)
        }
        guard let ref = FSEventStreamCreate(
            nil, callback, &context, [key] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(ref, queue)
        FSEventStreamStart(ref)
        stream.ref = ref
        streams[key] = stream
    }

    private func stop(_ stream: Stream) {
        guard let ref = stream.ref else { return }
        FSEventStreamStop(ref)
        FSEventStreamInvalidate(ref)
        FSEventStreamRelease(ref)
        stream.ref = nil
    }

    private func noteChange(key: String) {
        lock.lock(); defer { lock.unlock() }
        guard streams[key] != nil else { return }   // stopped since the event was queued
        changed[key] = true
    }
}

// MARK: - Read policy

/// When and how long the last status read of a repo took.
struct StatusReadRecord: Equatable, Sendable {
    let at: Date
    let duration: TimeInterval
}

enum StatusReadPolicy {
    /// A read slower than this marks the repo as slow.
    static let slowThreshold: TimeInterval = 1
    /// How long a slow repo waits before it may be read again, regardless of
    /// how often its tree changes. Matches the default background cadence.
    static let slowInterval: TimeInterval = 300

    /// True while a slow repo is still inside its long interval. Checked
    /// *before* consuming the change flag, so a change seen during the wait
    /// isn't swallowed — it's still pending when the interval ends.
    static func isInSlowBackoff(_ lastRead: StatusReadRecord?, now: Date) -> Bool {
        guard let lastRead, lastRead.duration > slowThreshold else { return false }
        return now.timeIntervalSince(lastRead.at) < slowInterval
    }

    static func shouldRead(changed: Bool, lastRead: StatusReadRecord?, now: Date) -> Bool {
        changed && !isInSlowBackoff(lastRead, now: now)
    }
}

/// Per-repo memory of the last read, shared across the poller's concurrent
/// per-repo tasks.
final class StatusReadLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [UUID: StatusReadRecord] = [:]

    func record(for repoId: UUID) -> StatusReadRecord? {
        lock.lock(); defer { lock.unlock() }
        return records[repoId]
    }

    func set(_ record: StatusReadRecord, for repoId: UUID) {
        lock.lock(); defer { lock.unlock() }
        records[repoId] = record
    }
}
