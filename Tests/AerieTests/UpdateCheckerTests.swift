import XCTest
@testable import Aerie

final class UpdateCheckerTests: XCTestCase {
    func test_semanticVersion_parsesAndStripsVPrefix() {
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion("1.2.3"))
        XCTAssertEqual(SemanticVersion("1.2.3")?.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("v0.3.1")?.description, "0.3.1")
    }

    func test_semanticVersion_comparison() {
        XCTAssertTrue(SemanticVersion("1.0.0")! < SemanticVersion("1.0.1")!)
        XCTAssertTrue(SemanticVersion("1.2.0")! < SemanticVersion("2.0.0")!)
        XCTAssertTrue(SemanticVersion("1.9.9")! < SemanticVersion("2.0.0")!)
        XCTAssertFalse(SemanticVersion("2.0.0")! < SemanticVersion("1.9.9")!)
        XCTAssertFalse(SemanticVersion("1.2.3")! < SemanticVersion("1.2.3")!)
    }

    func test_semanticVersion_rejectsMalformed() {
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("1.2.x"))
        XCTAssertNil(SemanticVersion("0.3.1-beta"))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("dev"))
    }

    // MARK: - Task 2: fetcher + check()

    private struct StubFetcher: ReleaseFetching {
        let result: Result<(tag: String, url: URL), Error>
        func latestRelease() async throws -> (tag: String, url: URL) { try result.get() }
    }

    private let sampleURL = URL(string: "https://github.com/echoulen/Aerie/releases/tag/v0.4.0")!

    func test_check_updateAvailable_whenLatestHigher() async {
        let checker = UpdateChecker(current: "0.3.1",
                                    fetcher: StubFetcher(result: .success(("v0.4.0", sampleURL))))
        let outcome = await checker.check()
        XCTAssertEqual(outcome,
                       .updateAvailable(current: "0.3.1", latest: "0.4.0", url: sampleURL))
    }

    func test_check_upToDate_whenEqual() async {
        let checker = UpdateChecker(current: "0.3.1",
                                    fetcher: StubFetcher(result: .success(("v0.3.1", sampleURL))))
        let outcome = await checker.check()
        XCTAssertEqual(outcome, .upToDate(current: "0.3.1"))
    }

    func test_check_upToDate_whenLocalNewer() async {
        let checker = UpdateChecker(current: "0.3.1",
                                    fetcher: StubFetcher(result: .success(("v0.3.0", sampleURL))))
        let outcome = await checker.check()
        XCTAssertEqual(outcome, .upToDate(current: "0.3.1"))
    }

    func test_check_failed_whenFetchThrows() async {
        struct E: Error {}
        let checker = UpdateChecker(current: "0.3.1",
                                    fetcher: StubFetcher(result: .failure(E())))
        guard case .failed = await checker.check() else { return XCTFail("expected .failed") }
    }

    func test_check_failed_whenTagUnparseable() async {
        let checker = UpdateChecker(current: "0.3.1",
                                    fetcher: StubFetcher(result: .success(("garbage", sampleURL))))
        guard case .failed = await checker.check() else { return XCTFail("expected .failed") }
    }

    func test_check_failed_whenCurrentUnparseable() async {
        let checker = UpdateChecker(current: "dev",
                                    fetcher: StubFetcher(result: .success(("v0.4.0", sampleURL))))
        guard case .failed = await checker.check() else { return XCTFail("expected .failed") }
    }

    func test_parse_extractsTagNameAndHtmlURL() throws {
        let json = #"{"tag_name":"v0.4.0","html_url":"https://github.com/echoulen/Aerie/releases/tag/v0.4.0","other":1}"#
            .data(using: .utf8)!
        let (tag, url) = try GitHubReleaseFetcher.parse(json)
        XCTAssertEqual(tag, "v0.4.0")
        XCTAssertEqual(url.absoluteString, "https://github.com/echoulen/Aerie/releases/tag/v0.4.0")
    }
}
