import XCTest
@testable import Aerie

final class ClaudeStreamParsingTests: XCTestCase {
    // Startup and in-flight signals, so the console isn't blank while claude
    // boots or thinks through a large diff.

    func test_systemInit_becomesSessionStartedProgress() {
        let line = #"{"type":"system","subtype":"init","model":"claude-sonnet-5","tools":["Read","Grep","Glob"]}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .progress("› session started · claude-sonnet-5 · 3 tools"))
    }

    func test_hookStarted_becomesProgress() {
        let line = #"{"type":"system","subtype":"hook_started","hook_name":"SessionStart:startup"}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .progress("› running hook SessionStart:startup"))
    }

    func test_otherSystemLines_ignored() {
        XCTAssertEqual(ClaudeStreamParsing.parseLine(#"{"type":"system","subtype":"hook_response"}"#), .ignored)
        XCTAssertEqual(ClaudeStreamParsing.parseLine(#"{"type":"system","subtype":"status","status":"requesting"}"#), .ignored)
        XCTAssertEqual(ClaudeStreamParsing.parseLine(#"{"type":"system","subtype":"thinking_tokens","estimated_tokens":50}"#), .ignored)
    }

    func test_thinkingBlockStart_becomesProgress() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .progress("› thinking…"))
    }

    func test_textBlockStart_becomesProgress() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(line), .progress("› writing…"))
    }

    func test_toolUseBlockStartAndDeltas_ignored() {
        // The completed `assistant` event names the tool with its input.
        let start = #"{"type":"stream_event","event":{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","name":"Read"}}}"#
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}}"#
        XCTAssertEqual(ClaudeStreamParsing.parseLine(start), .ignored)
        XCTAssertEqual(ClaudeStreamParsing.parseLine(delta), .ignored)
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
