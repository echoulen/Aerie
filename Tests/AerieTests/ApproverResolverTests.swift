import XCTest
@testable import Aerie

final class ApproverResolverTests: XCTestCase {
    private func acc(_ login: String, _ id: UUID = UUID()) -> GitHubAccount {
        GitHubAccount(id: id, login: login, host: "github.com")
    }

    func test_boundAccountEligible_isDefault() {
        let boundId = UUID()
        let accounts = [acc("reviewer", boundId), acc("someoneElse")]
        let r = ApproverResolver.resolve(
            accounts: accounts, boundAccountId: boundId, authorLogin: "octocat")
        XCTAssertEqual(r.defaultApprover?.id, boundId)
        XCTAssertTrue(r.canApprove)
    }

    func test_ownPR_boundIsAuthor_picksOtherAccount() {
        let boundId = UUID()
        let other = acc("teammate")
        let accounts = [acc("echoulen", boundId), other]
        let r = ApproverResolver.resolve(
            accounts: accounts, boundAccountId: boundId, authorLogin: "echoulen")
        XCTAssertEqual(r.defaultApprover?.id, other.id)
        XCTAssertEqual(r.eligible.map(\.login), ["teammate"])
    }

    func test_onlyAuthorConfigured_cannotApprove() {
        let boundId = UUID()
        let accounts = [acc("echoulen", boundId)]
        let r = ApproverResolver.resolve(
            accounts: accounts, boundAccountId: boundId, authorLogin: "echoulen")
        XCTAssertNil(r.defaultApprover)
        XCTAssertFalse(r.canApprove)
        XCTAssertTrue(r.eligible.isEmpty)
    }

    func test_authorMatchIsCaseInsensitive() {
        let boundId = UUID()
        let accounts = [acc("EchoULen", boundId), acc("teammate")]
        let r = ApproverResolver.resolve(
            accounts: accounts, boundAccountId: boundId, authorLogin: "echoulen")
        XCTAssertEqual(r.defaultApprover?.login, "teammate")
    }

    func test_multipleEligible_needsPicker() {
        let boundId = UUID()
        let accounts = [acc("reviewer", boundId), acc("teammate"), acc("third")]
        let r = ApproverResolver.resolve(
            accounts: accounts, boundAccountId: boundId, authorLogin: "octocat")
        XCTAssertTrue(r.needsPicker)
        XCTAssertEqual(r.eligible.count, 3)
        // Bound account still wins as the default.
        XCTAssertEqual(r.defaultApprover?.id, boundId)
    }

    func test_singleEligible_noPicker() {
        let boundId = UUID()
        let accounts = [acc("reviewer", boundId)]
        let r = ApproverResolver.resolve(
            accounts: accounts, boundAccountId: boundId, authorLogin: "octocat")
        XCTAssertFalse(r.needsPicker)
    }
}
