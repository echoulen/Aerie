import XCTest
@testable import Aerie

final class ModelsTests: XCTestCase {
    func test_repositoryRoundTrip() throws {
        let original = Repository(
            id: UUID(),
            name: "aerie",
            localPath: URL(fileURLWithPath: "/tmp/aerie"),
            githubOwner: "echoulen",
            githubRepo: "Aerie",
            defaultBranch: "main",
            primaryAccountId: UUID(),
            sortOrder: 0,
            hidden: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Repository.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_githubAccountRoundTrip() throws {
        let original = GitHubAccount(
            id: UUID(),
            login: "carlos-li",
            host: "github.com"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubAccount.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_localGitStatusRoundTrip() throws {
        let original = LocalGitStatus(
            repoId: UUID(),
            currentBranch: "feat/phase2-models",
            isDirty: true,
            dirtyFileCount: 3,
            aheadOfDefault: 2,
            behindOfDefault: 1,
            unpushedCommits: 2,
            originDefaultSha: "abc1234",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalGitStatus.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_pullRequestRoundTrip() throws {
        let original = PullRequest(
            id: UUID(),
            repoId: UUID(),
            number: 42,
            title: "Add virtual clock",
            authorLogin: "carlos-li",
            sourceBranch: "feat/virtual-clock",
            isMine: true,
            state: .open,
            ciState: .pending,
            reviewState: .reviewRequired,
            labels: ["enhancement", "needs-review"],
            htmlUrl: URL(string: "https://github.com/echoulen/Aerie/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PullRequest.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_prLocalStateRoundTripWithOptionalsSet() throws {
        let original = PRLocalState(
            prId: UUID(),
            sourceBranch: "feat/virtual-clock",
            localBranchExists: true,
            isCurrentBranch: true,
            dirty: true,
            ahead: 3,
            behind: 1,
            unpushed: 2
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PRLocalState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_mcpActivityRecordRoundTrip() throws {
        let original = MCPActivityRecord(
            id: 42,
            at: Date(timeIntervalSince1970: 1_700_000_000),
            agentId: "agent-abc",
            tool: "git.status",
            target: "/tmp/example",
            isWrite: false,
            ok: true,
            errorMessage: nil,
            requestJSON: "{\"path\":\"/tmp/example\"}",
            responseJSON: "{\"dirty\":false}"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPActivityRecord.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_prLocalStateRoundTripWithOptionalsNil() throws {
        let original = PRLocalState(
            prId: UUID(),
            sourceBranch: "feat/other",
            localBranchExists: true,
            isCurrentBranch: false,
            dirty: nil,
            ahead: nil,
            behind: nil,
            unpushed: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PRLocalState.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
