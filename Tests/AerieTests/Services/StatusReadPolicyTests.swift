import XCTest
@testable import Aerie

/// Decides whether a polling tick re-reads a repo's git status. Two gates:
/// the working tree must have changed since the last read, and a repo whose
/// last read was slow only re-reads on the long cadence — an editor writing
/// into an ignored tree every few seconds would otherwise defeat the change
/// gate and burn seconds of libgit2 every tick.
final class StatusReadPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func test_neverRead_reads() {
        XCTAssertTrue(StatusReadPolicy.shouldRead(changed: true, lastRead: nil, now: t0))
    }

    func test_unchanged_skips() {
        let fast = StatusReadRecord(at: t0, duration: 0.05)
        XCTAssertFalse(StatusReadPolicy.shouldRead(changed: false, lastRead: fast, now: t0.addingTimeInterval(30)))
    }

    func test_changed_afterFastRead_reads() {
        let fast = StatusReadRecord(at: t0, duration: 0.05)
        XCTAssertTrue(StatusReadPolicy.shouldRead(changed: true, lastRead: fast, now: t0.addingTimeInterval(30)))
    }

    func test_changed_afterSlowRead_waitsForTheSlowInterval() {
        let slow = StatusReadRecord(at: t0, duration: StatusReadPolicy.slowThreshold + 1)
        XCTAssertFalse(StatusReadPolicy.shouldRead(
            changed: true, lastRead: slow, now: t0.addingTimeInterval(30)),
            "a slow repo doesn't re-read on the regular cadence")
        XCTAssertFalse(StatusReadPolicy.shouldRead(
            changed: true, lastRead: slow, now: t0.addingTimeInterval(StatusReadPolicy.slowInterval - 1)))
        XCTAssertTrue(StatusReadPolicy.shouldRead(
            changed: true, lastRead: slow, now: t0.addingTimeInterval(StatusReadPolicy.slowInterval)))
    }

    func test_unchanged_afterSlowRead_stillSkips_evenPastTheSlowInterval() {
        let slow = StatusReadRecord(at: t0, duration: 10)
        XCTAssertFalse(StatusReadPolicy.shouldRead(
            changed: false, lastRead: slow, now: t0.addingTimeInterval(StatusReadPolicy.slowInterval * 2)))
    }

    func test_thresholds() {
        XCTAssertEqual(StatusReadPolicy.slowThreshold, 1)
        XCTAssertEqual(StatusReadPolicy.slowInterval, 300)
    }
}
