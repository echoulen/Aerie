import XCTest
@testable import Aerie

final class GhAuthStatusParserTests: XCTestCase {
    func test_parsesMultiAccount() {
        let fixture = """
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
        let accounts = GhAuthStatusParser.parse(stdout: fixture)
        XCTAssertEqual(accounts.count, 2)
        XCTAssertTrue(accounts.contains { $0.login == "carlos-li" })
        let carlos = accounts.first { $0.login == "carlos-li" }
        XCTAssertEqual(carlos?.scopes, ["repo", "read:org"])
    }

    func test_parsesSingleAccount() {
        let fixture = """
        github.com
          ✓ Logged in to github.com account foo (keyring)
          - Active account: true
          - Git operations protocol: ssh
          - Token: gho_••••••
          - Token scopes: 'repo'
        """
        let accounts = GhAuthStatusParser.parse(stdout: fixture)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.login, "foo")
        XCTAssertEqual(accounts.first?.host, "github.com")
        XCTAssertEqual(accounts.first?.active, true)
    }

    func test_parsesNoAuth() {
        let fixture = "You are not logged into any GitHub hosts. To log in, run: gh auth login"
        let accounts = GhAuthStatusParser.parse(stdout: fixture)
        XCTAssertEqual(accounts.count, 0)
    }

    func test_parsesGheHost() {
        let fixture = """
        mycorp.ghe.com
          ✓ Logged in to mycorp.ghe.com account enterprise-user (keyring)
          - Active account: true
          - Git operations protocol: https
          - Token: gho_••••••
          - Token scopes: 'repo', 'read:org', 'workflow'
        """
        let accounts = GhAuthStatusParser.parse(stdout: fixture)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.host, "mycorp.ghe.com")
        XCTAssertEqual(accounts.first?.login, "enterprise-user")
        XCTAssertEqual(accounts.first?.scopes, ["repo", "read:org", "workflow"])
    }
}
