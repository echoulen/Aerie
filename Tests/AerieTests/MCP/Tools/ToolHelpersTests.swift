import XCTest
@testable import Aerie

final class ToolHelpersTests: XCTestCase {
    func test_stringParam_returnsValue() throws {
        let p = JSONValue.object(["branch": .string("feat/x")])
        XCTAssertEqual(try stringParam(p, key: "branch"), "feat/x")
    }

    func test_stringParam_missing_throwsInvalidParams() {
        let p = JSONValue.object([:])
        XCTAssertThrowsError(try stringParam(p, key: "branch")) { err in
            XCTAssertEqual((err as? JSONRPCError)?.code, -32602)
        }
    }

    func test_stringParam_empty_throwsInvalidParams() {
        let p = JSONValue.object(["branch": .string("")])
        XCTAssertThrowsError(try stringParam(p, key: "branch")) { err in
            XCTAssertEqual((err as? JSONRPCError)?.code, -32602)
        }
    }

    func test_optionalStringParam_absentReturnsNil() {
        XCTAssertNil(optionalStringParam(.object([:]), key: "body"))
    }

    func test_boolParam_absentReturnsDefault() {
        XCTAssertTrue(boolParam(.object([:]), key: "force", default: true))
        XCTAssertFalse(boolParam(.object([:]), key: "force", default: false))
    }

    func test_boolParam_present() {
        XCTAssertTrue(boolParam(.object(["force": .bool(true)]), key: "force", default: false))
    }
}
