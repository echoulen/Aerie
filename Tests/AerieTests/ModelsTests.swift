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

    func test_claudeModel_rawValuesAndDisplayNames() {
        XCTAssertEqual(ClaudeModel.sonnet5.rawValue, "claude-sonnet-5")
        XCTAssertEqual(ClaudeModel.opus48.rawValue, "claude-opus-4-8")
        XCTAssertEqual(ClaudeModel.haiku45.rawValue, "claude-haiku-4-5-20251001")
        XCTAssertEqual(ClaudeModel.fable5.rawValue, "claude-fable-5")

        XCTAssertEqual(ClaudeModel.sonnet5.displayName, "Sonnet 5")
        XCTAssertEqual(ClaudeModel.opus48.displayName, "Opus 4.8")
        XCTAssertEqual(ClaudeModel.haiku45.displayName, "Haiku 4.5")
        XCTAssertEqual(ClaudeModel.fable5.displayName, "Fable 5")
    }

    func test_claudeModel_allCases_hasExactlyFourInOrder() {
        XCTAssertEqual(ClaudeModel.allCases, [.sonnet5, .opus48, .haiku45, .fable5])
    }

    func test_claudeModel_default_isSonnet5() {
        XCTAssertEqual(ClaudeModel.default, .sonnet5)
    }

    func test_claudeModel_rawValueRoundTrip() {
        for model in ClaudeModel.allCases {
            XCTAssertEqual(ClaudeModel(rawValue: model.rawValue), model)
        }
        XCTAssertNil(ClaudeModel(rawValue: "not-a-real-model"))
    }
}
