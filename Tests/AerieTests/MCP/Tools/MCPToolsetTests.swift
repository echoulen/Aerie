import XCTest
@testable import Aerie

final class MCPToolsetTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs.removeAll()
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    func test_registerAll_registersTheFullRoster() async throws {
        let db = try makeDB()
        let registry = MCPToolRegistry()
        let api = MultiAccountAPI(
            client: LiveGitHubAPIClient(),
            tokensByAccount: { [:] },
            accountsInOrder: { [] }
        )

        await MCPToolset.registerAll(
            into: registry,
            db: db,
            git: LiveGitService(),
            api: api,
            accounts: { [] },
            refresh: { _ in },
            accountToken: { _ in nil }
        )

        guard case let .object(obj) = await registry.list(),
              case let .array(tools)? = obj["tools"] else {
            return XCTFail("unexpected tools/list shape")
        }
        let names = tools.compactMap { entry -> String? in
            if case let .object(t) = entry, case let .string(n)? = t["name"] { return n }
            return nil
        }.sorted()

        XCTAssertEqual(names, [
            "aerie_approve_pr",
            "aerie_cleanup_merged_branch",
            "aerie_discard_unstaged",
            "aerie_force_checkout",
            "aerie_get_local_status",
            "aerie_get_pr",
            "aerie_get_pr_diff",
            "aerie_get_pr_local_state",
            "aerie_hard_reset_to_default",
            "aerie_list_issues",
            "aerie_list_merged_branches",
            "aerie_list_prs",
            "aerie_list_repos",
            "aerie_list_worktrees",
            "aerie_merge_pr",
            "aerie_remove_worktree",
            "aerie_update_pr_branch",
            "aerie_worktree_discard",
            "aerie_worktree_merge",
        ])
    }
}
