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
        let result: Result<ReleaseInfo, Error>
        func latestRelease() async throws -> ReleaseInfo { try result.get() }
    }

    private let sampleURL = URL(string: "https://github.com/echoulen/Aerie/releases/tag/v0.4.0")!
    private let asset = "Aerie-macOS-arm64.zip"

    /// A published release carrying the installer zip `check()` looks for.
    private func release(_ tag: String, assets: [String]? = nil) -> ReleaseInfo {
        ReleaseInfo(tag: tag, url: sampleURL, assetNames: assets ?? [asset])
    }

    private func checker(current: String, _ result: Result<ReleaseInfo, Error>) -> UpdateChecker {
        UpdateChecker(current: current, assetName: asset, fetcher: StubFetcher(result: result))
    }

    func test_check_updateAvailable_whenLatestHigher() async {
        let outcome = await checker(current: "0.3.1", .success(release("v0.4.0"))).check()
        XCTAssertEqual(outcome,
                       .updateAvailable(current: "0.3.1", latest: "0.4.0", url: sampleURL))
    }

    /// The release is published before CI uploads its zip; offering the update
    /// in that window made the installer 404 and leave the app stuck.
    func test_check_notOffered_whileInstallerAssetMissing() async {
        let outcome = await checker(current: "0.3.1", .success(release("v0.4.0", assets: []))).check()
        guard case .failed(let message) = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertTrue(message.contains("0.4.0"))
    }

    func test_check_notOffered_whenOnlyOtherArchitectureAssetExists() async {
        let outcome = await checker(current: "0.3.1",
                                    .success(release("v0.4.0", assets: ["Aerie-macOS-x86_64.zip"]))).check()
        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
    }

    func test_check_upToDate_whenEqual_evenWithoutAsset() async {
        let outcome = await checker(current: "0.4.0", .success(release("v0.4.0", assets: []))).check()
        XCTAssertEqual(outcome, .upToDate(current: "0.4.0"))
    }

    func test_check_upToDate_whenEqual() async {
        let outcome = await checker(current: "0.3.1", .success(release("v0.3.1"))).check()
        XCTAssertEqual(outcome, .upToDate(current: "0.3.1"))
    }

    func test_check_upToDate_whenLocalNewer() async {
        let outcome = await checker(current: "0.3.1", .success(release("v0.3.0"))).check()
        XCTAssertEqual(outcome, .upToDate(current: "0.3.1"))
    }

    func test_check_failed_whenFetchThrows() async {
        struct E: Error {}
        guard case .failed = await checker(current: "0.3.1", .failure(E())).check() else { return XCTFail("expected .failed") }
    }

    func test_check_failed_whenTagUnparseable() async {
        guard case .failed = await checker(current: "0.3.1", .success(release("garbage"))).check() else { return XCTFail("expected .failed") }
    }

    func test_check_failed_whenCurrentUnparseable() async {
        guard case .failed = await checker(current: "dev", .success(release("v0.4.0"))).check() else { return XCTFail("expected .failed") }
    }

    func test_parse_extractsTagNameHtmlURLAndAssetNames() throws {
        let json = #"{"tag_name":"v0.4.0","html_url":"https://github.com/echoulen/Aerie/releases/tag/v0.4.0","assets":[{"name":"Aerie-macOS-arm64.zip","size":1}],"other":1}"#
            .data(using: .utf8)!
        let info = try GitHubReleaseFetcher.parse(json)
        XCTAssertEqual(info.tag, "v0.4.0")
        XCTAssertEqual(info.url.absoluteString, "https://github.com/echoulen/Aerie/releases/tag/v0.4.0")
        XCTAssertEqual(info.assetNames, ["Aerie-macOS-arm64.zip"])
    }

    func test_parse_treatsMissingAssetsAsEmpty() throws {
        let json = #"{"tag_name":"v0.4.0","html_url":"https://github.com/echoulen/Aerie/releases/tag/v0.4.0"}"#
            .data(using: .utf8)!
        XCTAssertEqual(try GitHubReleaseFetcher.parse(json).assetNames, [])
    }

    func test_installerAssetName_matchesInstallScriptNaming() {
        #if arch(arm64)
        XCTAssertEqual(UpdateChecker.installerAssetName, "Aerie-macOS-arm64.zip")
        #else
        XCTAssertEqual(UpdateChecker.installerAssetName, "Aerie-macOS-x86_64.zip")
        #endif
    }
}
