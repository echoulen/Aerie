import XCTest
@testable import Aerie

final class ClaudeReviewParsingTests: XCTestCase {
    // MARK: parse

    func test_parse_envelopeWithFencedJSON_approve() {
        let stdout = """
        {"type":"result","is_error":false,"result":"Here is my review.\\n```json\\n{\\"verdict\\":\\"approve\\",\\"summary\\":\\"LGTM\\",\\"issues\\":[]}\\n```"}
        """
        let review = ClaudeReviewParsing.parse(stdout: stdout)
        XCTAssertEqual(review?.verdict, .approve)
        XCTAssertEqual(review?.summary, "LGTM")
        XCTAssertEqual(review?.issues, [])
    }

    func test_parse_bareJSON_noEnvelope_issuesFound() {
        let stdout = #"{"verdict":"issues_found","summary":"Found a bug","issues":["null deref in A.swift"]}"#
        let review = ClaudeReviewParsing.parse(stdout: stdout)
        XCTAssertEqual(review?.verdict, .issuesFound)
        XCTAssertEqual(review?.issues, ["null deref in A.swift"])
    }

    func test_parse_envelopeResultWithSurroundingProse() {
        let stdout = #"{"type":"result","result":"My verdict:\n{\"verdict\":\"approve\",\"summary\":\"ok\",\"issues\":[]}\nDone."}"#
        XCTAssertEqual(ClaudeReviewParsing.parse(stdout: stdout)?.verdict, .approve)
    }

    func test_parse_missingIssuesField_defaultsToEmpty() {
        let stdout = #"{"verdict":"approve","summary":"ok"}"#
        XCTAssertEqual(ClaudeReviewParsing.parse(stdout: stdout)?.issues, [])
    }

    func test_parse_unknownVerdict_returnsNil() {
        let stdout = #"{"verdict":"maybe","summary":"unsure","issues":[]}"#
        XCTAssertNil(ClaudeReviewParsing.parse(stdout: stdout))
    }

    func test_parse_noJSON_returnsNil() {
        XCTAssertNil(ClaudeReviewParsing.parse(stdout: "claude crashed, no output"))
    }

    func test_parse_garbageJSON_returnsNil() {
        XCTAssertNil(ClaudeReviewParsing.parse(stdout: "{not valid json"))
    }

    // MARK: diffText

    func test_diffText_includesFilenameStatusAndPatch() {
        let files = [
            PRFileChange(filename: "A.swift", status: .modified, additions: 3, deletions: 1, patch: "@@ -1 +1 @@\n-a\n+b"),
            PRFileChange(filename: "img.png", status: .added, additions: 0, deletions: 0, patch: nil),
        ]
        let text = ClaudeReviewPrompt.diffText(files: files)
        XCTAssertTrue(text.contains("A.swift"))
        XCTAssertTrue(text.contains("@@ -1 +1 @@"))
        XCTAssertTrue(text.contains("img.png"))
        XCTAssertTrue(text.contains("no textual diff"))
    }

    // MARK: build

    func test_build_embedsPRMetadataAndDiff() {
        let prompt = ClaudeReviewPrompt.build(
            owner: "echoulen", repo: "aerie", number: 42,
            title: "Add review screen", author: "octocat",
            sourceBranch: "feat/x", diff: "DIFF-BODY")
        XCTAssertTrue(prompt.contains("#42"))
        XCTAssertTrue(prompt.contains("Add review screen"))
        XCTAssertTrue(prompt.contains("DIFF-BODY"))
        XCTAssertTrue(prompt.contains("\"verdict\""))
    }
}
