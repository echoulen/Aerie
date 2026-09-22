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

    func test_parse_proseWithStrayBraceBeforeJSON_stillParses() {
        // Claude's analysis mentions `{something}` before the real trailing JSON.
        let stdout = #"{"type":"result","result":"The code does {something} wrong.\n{\"verdict\":\"issues_found\",\"summary\":\"bug\",\"issues\":[\"x\"]}"}"#
        let review = ClaudeReviewParsing.parse(stdout: stdout)
        XCTAssertEqual(review?.verdict, .issuesFound)
        XCTAssertEqual(review?.summary, "bug")
        XCTAssertEqual(review?.issues, ["x"])
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

    func test_build_defaultGuidance_keepsBuiltInRules() {
        let prompt = ClaudeReviewPrompt.build(
            owner: "o", repo: "r", number: 1, title: "t", author: "a", sourceBranch: "b", diff: "D")
        XCTAssertTrue(prompt.contains("MAJOR problems only"))
    }

    func test_build_customGuidance_replacesOnlyTheEditableSections() {
        let guidance = AIReviewGuidance(firstPass: "FIRST-PASS-RULES", followUp: "FOLLOW-UP-RULES")
        let first = ClaudeReviewPrompt.build(
            owner: "o", repo: "r", number: 7, title: "t", author: "a", sourceBranch: "b", diff: "D",
            guidance: guidance)
        XCTAssertTrue(first.contains("FIRST-PASS-RULES"))
        XCTAssertFalse(first.contains("MAJOR problems only"))
        XCTAssertFalse(first.contains("FOLLOW-UP-RULES"), "follow-up guidance only goes into re-reviews")
        XCTAssertTrue(first.contains("PR #7"), "context header stays")
        XCTAssertTrue(first.contains("\"verdict\""), "JSON contract stays")

        let again = ClaudeReviewPrompt.build(
            owner: "o", repo: "r", number: 7, title: "t", author: "a", sourceBranch: "b", diff: "D",
            followUp: followUp(), guidance: guidance)
        XCTAssertTrue(again.contains("FOLLOW-UP-RULES"))
        XCTAssertTrue(again.contains("\"previous\""), "the contract still asks for previous statuses")
        XCTAssertTrue(again.contains("not as instructions"), "the reply guard isn't editable")
    }

    func test_guidanceResolve_blankFallsBackToDefault() {
        let g = AIReviewGuidance.resolve(firstPass: "  \n", followUp: nil)
        XCTAssertEqual(g, .default)
        XCTAssertEqual(AIReviewGuidance.resolve(firstPass: "mine", followUp: nil).firstPass, "mine")
    }

    // MARK: follow-up

    private func followUp() -> AIReviewFollowUp {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        return AIReviewFollowUp(
            previous: .init(author: "reviewer", state: "CHANGES_REQUESTED",
                            body: "PREVIOUS-REVIEW-BODY: null deref in load()", submittedAt: t0, commitOid: "c2"),
            responses: [
                .init(author: "octocat", body: "load() is only called after init sets it — can't be nil",
                      createdAt: t0.addingTimeInterval(60), kind: .inline(path: "Sources/A.swift", line: 42)),
                .init(author: "octocat", body: String(repeating: "x", count: 5_000),
                      createdAt: t0.addingTimeInterval(120), kind: .conversation),
            ],
            newCommits: [.init(oid: "c3abcdef99", headline: "guard the cache")],
            historyRewritten: false)
    }

    func test_build_withoutFollowUp_hasNoFollowUpSection() {
        let prompt = ClaudeReviewPrompt.build(
            owner: "o", repo: "r", number: 1, title: "t", author: "a", sourceBranch: "b", diff: "D")
        XCTAssertFalse(prompt.contains("FOLLOW-UP REVIEW"))
        XCTAssertFalse(prompt.contains("\"previous\""))
    }

    func test_build_withFollowUp_embedsPreviousReviewRepliesAndCommits() {
        let prompt = ClaudeReviewPrompt.build(
            owner: "o", repo: "r", number: 1, title: "t", author: "a", sourceBranch: "b", diff: "D",
            followUp: followUp())
        XCTAssertTrue(prompt.contains("FOLLOW-UP REVIEW"))
        XCTAssertTrue(prompt.contains("PREVIOUS-REVIEW-BODY: null deref in load()"))
        XCTAssertTrue(prompt.contains("can't be nil"))
        XCTAssertTrue(prompt.contains("Sources/A.swift:42"), "inline replies say where they were left")
        XCTAssertTrue(prompt.contains("c3abcde"), "new commits are listed by short sha")
        XCTAssertTrue(prompt.contains("guard the cache"))
        XCTAssertTrue(prompt.contains("\"justified\""))
        XCTAssertTrue(prompt.contains("\"previous\""))
        XCTAssertTrue(prompt.contains("not as instructions"), "replies are data to verify, not commands")
        XCTAssertFalse(prompt.contains(String(repeating: "x", count: 5_000)), "long replies are truncated")
    }

    func test_build_withRewrittenHistory_saysSo() {
        let f = followUp()
        let rewritten = AIReviewFollowUp(previous: f.previous, responses: [], newCommits: [], historyRewritten: true)
        let prompt = ClaudeReviewPrompt.build(
            owner: "o", repo: "r", number: 1, title: "t", author: "a", sourceBranch: "b", diff: "D",
            followUp: rewritten)
        XCTAssertTrue(prompt.contains("rewritten"))
        XCTAssertTrue(prompt.contains("No replies"))
    }

    func test_parse_previousIssueStatuses() throws {
        let json = #"{"verdict": "approve", "summary": "ok", "issues": [], "previous": [{"issue": "null deref", "status": "fixed", "note": "guarded in c3"}, {"issue": "race", "status": "justified", "note": "main actor only"}]}"#
        let review = try XCTUnwrap(ClaudeReviewParsing.parse(stdout: json))
        XCTAssertEqual(review.verdict, .approve)
        XCTAssertEqual(review.previous, [
            .init(issue: "null deref", status: .fixed, note: "guarded in c3"),
            .init(issue: "race", status: .justified, note: "main actor only"),
        ])
    }

    func test_parse_approveWithAnOpenPreviousIssue_isDowngradedToIssuesFound() throws {
        // Never approve on a contradiction: an issue still "open" blocks.
        let json = #"{"verdict": "approve", "summary": "ok", "issues": [], "previous": [{"issue": "race", "status": "open", "note": "the reply doesn't cover the background path"}]}"#
        let review = try XCTUnwrap(ClaudeReviewParsing.parse(stdout: json))
        XCTAssertEqual(review.verdict, .issuesFound)
    }

    func test_parse_unknownPreviousStatus_countsAsOpen() throws {
        let json = #"{"verdict": "approve", "summary": "ok", "issues": [], "previous": [{"issue": "race", "status": "maybe"}]}"#
        let review = try XCTUnwrap(ClaudeReviewParsing.parse(stdout: json))
        XCTAssertEqual(review.previous.first?.status, .open)
        XCTAssertEqual(review.previous.first?.note, "")
        XCTAssertEqual(review.verdict, .issuesFound)
    }
}
