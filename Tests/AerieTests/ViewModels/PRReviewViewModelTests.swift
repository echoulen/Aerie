import XCTest
@testable import Aerie

@MainActor
final class PRReviewViewModelTests: XCTestCase {
    private let boundId = UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!

    private func makeRepo() -> Repository {
        Repository(
            id: UUID(), name: "aerie",
            localPath: URL(fileURLWithPath: "/tmp/aerie"),
            githubOwner: "echoulen", githubRepo: "aerie",
            defaultBranch: "main", primaryAccountId: boundId,
            sortOrder: 0, hidden: false)
    }

    private func makePR(author: String) -> PullRequest {
        PullRequest(
            id: UUID(), repoId: UUID(), number: 42, title: "Add review screen",
            authorLogin: author, sourceBranch: "feat/x", isMine: author == "echoulen",
            state: .open, ciState: .success, reviewState: .reviewRequired,
            labels: [], htmlUrl: URL(string: "https://example.com")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func row(author: String) -> PRRow {
        PRRow(pr: makePR(author: author), repo: makeRepo(), localState: nil)
    }

    private let file = PRFileChange(
        filename: "A.swift", status: .modified, additions: 3, deletions: 1, patch: "@@ -1 +1 @@\n-a\n+b")

    func test_load_withFiles_becomesReady() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { [GitHubAccount(id: self.boundId, login: "reviewer", host: "github.com")] })
        await vm.load()
        XCTAssertEqual(vm.state, .ready([file]))
    }

    func test_load_noFiles_becomesEmpty() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [] },
            accountsProvider: { [] })
        await vm.load()
        XCTAssertEqual(vm.state, .empty)
    }

    func test_load_throwing_becomesError() async {
        struct Boom: LocalizedError { var errorDescription: String? { "kaboom" } }
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in throw Boom() },
            accountsProvider: { [] })
        await vm.load()
        XCTAssertEqual(vm.state, .error("kaboom"))
    }

    func test_load_resolvesBoundAccountAsApprover() async {
        let vm = PRReviewViewModel(
            row: row(author: "octocat"),
            loadFiles: { _ in [self.file] },
            accountsProvider: { [GitHubAccount(id: self.boundId, login: "reviewer", host: "github.com")] })
        await vm.load()
        XCTAssertEqual(vm.resolution.defaultApprover?.id, boundId)
        XCTAssertTrue(vm.resolution.canApprove)
    }

    func test_load_ownPR_picksOtherAccountAsApprover() async {
        let other = GitHubAccount(id: UUID(), login: "teammate", host: "github.com")
        let vm = PRReviewViewModel(
            row: row(author: "echoulen"),
            loadFiles: { _ in [self.file] },
            accountsProvider: {
                [GitHubAccount(id: self.boundId, login: "echoulen", host: "github.com"), other]
            })
        await vm.load()
        XCTAssertEqual(vm.resolution.defaultApprover?.id, other.id)
    }
}
