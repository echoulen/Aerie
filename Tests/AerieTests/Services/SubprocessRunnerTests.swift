import XCTest
@testable import Aerie

final class SubprocessRunnerTests: XCTestCase {
    func test_runsTrueAndReturnsExitZero() async throws {
        let runner = LiveSubprocessRunner()
        let (_, _, rc) = try await runner.run("true", [])
        XCTAssertEqual(rc, 0)
    }
}
