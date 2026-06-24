import XCTest
@testable import Aerie

final class ClaudeStreamParsingTests: XCTestCase {
    func test_systemAndHookLines_ignored() {
        XCTAssertEqual(ClaudeStreamParsing.parseLine(#"{"type":"system","subtype":"init"}"#), .ignored)
        XCTAssertEqual(ClaudeStreamParsing.parseLine(#"{"type":"system","subtype":"hook_started","hook_name":"X"}"#), .ignored)
    }

    func test_assistantText_becomesProgress() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at the diff"}]}}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .progress("Looking at the diff"))
    }

    func test_assistantToolUse_read_becomesProgress() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"Sources/Foo.swift"}}]}}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .progress("Read Sources/Foo.swift"))
    }

    func test_assistantToolUse_grep_becomesProgress() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Grep","input":{"pattern":"force unwrap"}}]}}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .progress(#"Grep "force unwrap""#))
    }

    func test_userToolResult_ignored() {
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"..."}]}}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .ignored)
    }

    func test_resultLine_becomesFinalResult() {
        let line = #"{"type":"result","subtype":"success","result":"verdict text {\"verdict\":\"approve\"}"}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .finalResult(#"verdict text {"verdict":"approve"}"#))
    }

    func test_garbageLine_ignored() {
        XCTAssertEqual(ClaudeStreamParsing.parseLine("not json"), .ignored)
        XCTAssertEqual(ClaudeStreamParsing.parseLine(""), .ignored)
    }

    func test_emptyTextProgress_ignored() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"   "}]}}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .ignored)
    }
}
