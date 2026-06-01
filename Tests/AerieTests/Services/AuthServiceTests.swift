import XCTest
@testable import Aerie

final class MockSubprocessRunner: SubprocessRunner, @unchecked Sendable {
    var responses: [String: (String, String, Int32)] = [:]
    func run(_ command: String, _ args: [String]) async throws -> (String, String, Int32) {
        let key = ([command] + args).joined(separator: " ")
        return responses[key] ?? ("", "", 0)
    }
}

final class AuthServiceTests: XCTestCase {
    func test_bootstrap_returnsGhMissing_whenWhichFails() async throws {
        let mock = MockSubprocessRunner()
        mock.responses["which gh"] = ("", "", 1)
        let service = LiveAuthService(runner: mock)
        let result = try await service.bootstrap()
        XCTAssertEqual(result, .ghMissing)
    }

    func test_bootstrap_returnsGhMissing_whenWhichOutputEmpty() async throws {
        let mock = MockSubprocessRunner()
        mock.responses["which gh"] = ("", "", 0)
        let service = LiveAuthService(runner: mock)
        let result = try await service.bootstrap()
        XCTAssertEqual(result, .ghMissing)
    }

    func test_bootstrap_returnsNoAuth_whenStatusEmpty() async throws {
        let mock = MockSubprocessRunner()
        mock.responses["which gh"] = ("/opt/homebrew/bin/gh", "", 0)
        mock.responses["gh auth status"] = (
            "You are not logged into any GitHub hosts.",
            "",
            0
        )
        let service = LiveAuthService(runner: mock)
        let result = try await service.bootstrap()
        XCTAssertEqual(result, .noAuth)
    }

    func test_bootstrap_returnsOk_andFetchesTokens() async throws {
        let mock = MockSubprocessRunner()
        mock.responses["which gh"] = ("/opt/homebrew/bin/gh", "", 0)
        let statusFixture = """
        github.com
          ✓ Logged in to github.com account carlos-li (keyring)
          - Active account: true
          - Git operations protocol: ssh
          - Token: gho_••••••
          - Token scopes: 'repo', 'read:org'
          ✓ Logged in to github.com account cli-work (keyring)
          - Active account: false
          - Git operations protocol: https
          - Token: gho_••••••
          - Token scopes: 'repo'
        """
        mock.responses["gh auth status"] = (statusFixture, "", 0)
        mock.responses["gh auth token --hostname github.com --user carlos-li"] =
            ("ghp_fakeToken_carlos-li\n", "", 0)
        mock.responses["gh auth token --hostname github.com --user cli-work"] =
            ("ghp_fakeToken_cli-work\n", "", 0)

        let service = LiveAuthService(runner: mock)
        let result = try await service.bootstrap()

        guard case let .ok(accounts) = result else {
            return XCTFail("expected .ok, got \(result)")
        }
        XCTAssertEqual(accounts.count, 2)

        let all = await service.allAccounts()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(Set(all.map(\.login)), ["carlos-li", "cli-work"])

        for acct in all {
            let tok = await service.token(for: acct.id)
            XCTAssertEqual(tok, "ghp_fakeToken_\(acct.login)")
        }
    }
}
