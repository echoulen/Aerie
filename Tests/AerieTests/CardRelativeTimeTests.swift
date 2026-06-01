import XCTest
@testable import Aerie

/// Unit coverage for the card meta row's "updated …" relative-time label.
///
/// Locale is injected so the assertions are deterministic regardless of the
/// machine's region — the bug this guards against ("0秒後") is locale-specific,
/// but the underlying defect (a zero/future delta rendered in the future tense)
/// is not.
final class CardRelativeTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let enUS = Locale(identifier: "en_US")
    private let zhTW = Locale(identifier: "zh_Hant_TW")

    /// A PR updated this very instant must read as the localized "now", never
    /// the formatter's zero-delta future framing ("in 0 sec." / "0秒後").
    func test_label_atSameInstant_isNow() {
        XCTAssertEqual(CardRelativeTime.label(for: now, now: now, locale: enUS), "now")
        XCTAssertEqual(CardRelativeTime.label(for: now, now: now, locale: zhTW), "現在")
    }

    /// A timestamp a few seconds in the future (server/client clock skew) still
    /// reads as "now" — not "in 5 sec." / "5秒後".
    func test_label_futureClockSkew_isNow() {
        let future = now.addingTimeInterval(5)
        XCTAssertEqual(CardRelativeTime.label(for: future, now: now, locale: enUS), "now")
        XCTAssertEqual(CardRelativeTime.label(for: future, now: now, locale: zhTW), "現在")
    }

    /// A genuine past update still renders the clamped relative string.
    func test_label_pastUpdate_isRelativeString() {
        let past = now.addingTimeInterval(-30)
        XCTAssertEqual(CardRelativeTime.label(for: past, now: now, locale: enUS), "30 sec. ago")
    }
}
