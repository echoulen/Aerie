import XCTest
@testable import Aerie

final class DiffParserTests: XCTestCase {
    func test_nilPatch_yieldsNoHunks() {
        XCTAssertTrue(DiffParser.parse(patch: nil).isEmpty)
    }

    func test_emptyPatch_yieldsNoHunks() {
        XCTAssertTrue(DiffParser.parse(patch: "").isEmpty)
    }

    func test_singleHunk_classifiesLinesAndNumbers() {
        let patch = """
        @@ -10,3 +10,4 @@ func tick()
         let a = 1
        -let b = 2
        +let b = 3
        +let c = 4
        """
        let hunks = DiffParser.parse(patch: patch)
        XCTAssertEqual(hunks.count, 1)
        let lines = hunks[0].lines
        XCTAssertEqual(lines.count, 4)

        // context
        XCTAssertEqual(lines[0].kind, .context)
        XCTAssertEqual(lines[0].text, "let a = 1")
        XCTAssertEqual(lines[0].oldLineNo, 10)
        XCTAssertEqual(lines[0].newLineNo, 10)

        // deletion: advances old only
        XCTAssertEqual(lines[1].kind, .deletion)
        XCTAssertEqual(lines[1].text, "let b = 2")
        XCTAssertEqual(lines[1].oldLineNo, 11)
        XCTAssertNil(lines[1].newLineNo)

        // additions: advance new only
        XCTAssertEqual(lines[2].kind, .addition)
        XCTAssertEqual(lines[2].text, "let b = 3")
        XCTAssertNil(lines[2].oldLineNo)
        XCTAssertEqual(lines[2].newLineNo, 11)

        XCTAssertEqual(lines[3].kind, .addition)
        XCTAssertEqual(lines[3].newLineNo, 12)
    }

    func test_multipleHunks_resetLineNumbersFromHeader() {
        let patch = """
        @@ -1,2 +1,2 @@
         one
        -two
        +TWO
        @@ -50,1 +50,2 @@
         fifty
        +fifty-one
        """
        let hunks = DiffParser.parse(patch: patch)
        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks[0].lines.first?.oldLineNo, 1)
        XCTAssertEqual(hunks[1].lines.first?.oldLineNo, 50)
        XCTAssertEqual(hunks[1].lines.first?.newLineNo, 50)
        XCTAssertEqual(hunks[1].lines.last?.kind, .addition)
        XCTAssertEqual(hunks[1].lines.last?.newLineNo, 51)
    }

    func test_headerWithoutCounts_defaultsToOne() {
        let patch = """
        @@ -5 +5 @@
        -old
        +new
        """
        let hunks = DiffParser.parse(patch: patch)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].lines[0].oldLineNo, 5)
        XCTAssertEqual(hunks[0].lines[1].newLineNo, 5)
    }

    func test_skipsGitHeadersAndNoNewlineMarker() {
        let patch = """
        diff --git a/x.swift b/x.swift
        index 111..222 100644
        --- a/x.swift
        +++ b/x.swift
        @@ -1,1 +1,1 @@
        -a
        +b
        \\ No newline at end of file
        """
        let hunks = DiffParser.parse(patch: patch)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].lines.count, 2)
        XCTAssertEqual(hunks[0].lines[0].kind, .deletion)
        XCTAssertEqual(hunks[0].lines[1].kind, .addition)
    }

    func test_preservesEmptyContextLine() {
        // A context line that is just a single space (an empty source line).
        let patch = "@@ -1,2 +1,2 @@\n \n+x"
        let hunks = DiffParser.parse(patch: patch)
        XCTAssertEqual(hunks[0].lines[0].kind, .context)
        XCTAssertEqual(hunks[0].lines[0].text, "")
    }
}
