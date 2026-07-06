import XCTest
@testable import Aerie

final class PRCreateParsingTests: XCTestCase {
    func test_created_parsesNumberUrlSummary() {
        let text = """
        I pushed the branch and opened the PR.
        {"outcome": "created", "pr_number": 86, "pr_url": "https://github.com/echoulen/Aerie/pull/86", "summary": "新增 X"}
        """
        guard case .created(let n, let url, let summary)? = PRCreateParsing.parse(text: text)
        else { return XCTFail("expected .created") }
        XCTAssertEqual(n, 86)
        XCTAssertEqual(url.absoluteString, "https://github.com/echoulen/Aerie/pull/86")
        XCTAssertEqual(summary, "新增 X")
    }

    func test_created_missingNumber_isNil() {
        let text = #"{"outcome": "created", "pr_url": "https://github.com/e/r/pull/1", "summary": "s"}"#
        XCTAssertNil(PRCreateParsing.parse(text: text))
    }

    func test_created_unparseableUrl_isNil() {
        // Note: URL(string:) is lenient; an empty string is the reliable invalid case.
        let text = #"{"outcome": "created", "pr_number": 1, "pr_url": "", "summary": "s"}"#
        XCTAssertNil(PRCreateParsing.parse(text: text))
    }

    func test_nothingToDo_parses() {
        let text = #"{"outcome": "nothing_to_do", "summary": "工作區乾淨"}"#
        guard case .nothingToDo(let s)? = PRCreateParsing.parse(text: text)
        else { return XCTFail("expected .nothingToDo") }
        XCTAssertEqual(s, "工作區乾淨")
    }

    func test_failed_parsesSummary() {
        let text = #"{"outcome": "failed", "summary": "push 被拒"}"#
        guard case .failed(let m)? = PRCreateParsing.parse(text: text)
        else { return XCTFail("expected .failed") }
        XCTAssertEqual(m, "push 被拒")
    }

    func test_failed_withoutSummary_hasFallbackMessage() {
        let text = #"{"outcome": "failed"}"#
        guard case .failed(let m)? = PRCreateParsing.parse(text: text)
        else { return XCTFail("expected .failed") }
        XCTAssertFalse(m.isEmpty)
    }

    func test_unknownOutcome_isNil() {
        XCTAssertNil(PRCreateParsing.parse(text: #"{"outcome": "maybe"}"#))
    }

    func test_noJson_isNil() {
        XCTAssertNil(PRCreateParsing.parse(text: "I did some things but forgot the JSON."))
    }

    func test_bracesInProse_stillFindsLastObject() {
        let text = """
        The diff touches {a, b} and {c}.
        {"outcome": "nothing_to_do", "summary": "ok"}
        """
        guard case .nothingToDo? = PRCreateParsing.parse(text: text)
        else { return XCTFail("expected .nothingToDo") }
    }
}
