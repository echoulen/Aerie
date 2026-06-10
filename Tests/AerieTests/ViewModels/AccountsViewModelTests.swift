import XCTest
import GRDB
@testable import Aerie

/// Minimal `AccountUsageTracker` stub for the VM. Returns whatever timestamps
/// the test seeds, no I/O.
private actor StubAccountUsageTracker: AccountUsageTracker {
    private var values: [UUID: Date]

    init(_ values: [UUID: Date] = [:]) {
        self.values = values
    }

    func lastUsed(forAccount accountId: UUID) async -> Date? {
        values[accountId]
    }
}

@MainActor
final class AccountsViewModelTests: XCTestCase {
    // MARK: - Helpers

    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
    }

    private func makeDB() throws -> AppDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".sqlite")
        tempURLs.append(url)
        return try AppDatabase(url: url)
    }

    @discardableResult
    private func insertAccount(
        _ db: AppDatabase,
        id: UUID = UUID(),
        login: String = "tester",
        host: String = "github.com"
    ) throws -> GitHubAccount {
        let acct = GitHubAccount(id: id, login: login, host: host)
        try db.dbQueue.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO accounts (id, login, host) VALUES (?, ?, ?)",
                arguments: [acct.id.uuidString, acct.login, acct.host]
            )
        }
        return acct
    }

    private func insertRepo(
        _ db: AppDatabase,
        accountId: UUID,
        name: String,
        sortOrder: Int = 0
    ) async throws -> Repository {
        let r = Repository(
            id: UUID(),
            name: name,
            localPath: URL(fileURLWithPath: "/tmp/\(name)"),
            githubOwner: "octocat",
            githubRepo: name.lowercased(),
            defaultBranch: "main",
            primaryAccountId: accountId,
            sortOrder: sortOrder,
            hidden: false
        )
        try await db.repos.insert(r)
        return r
    }

    private func makeVM(
        db: AppDatabase,
        api: any AccountUsageTracker = StubAccountUsageTracker(),
        scopes: [UUID: [String]] = [:],
        primary: UUID? = nil
    ) -> AccountsViewModel {
        AccountsViewModel(
            db: db,
            api: api,
            scopesByAccount: { scopes },
            primaryAccountId: { primary }
        )
    }

    // MARK: - Tests

    func test_refresh_emitsRowsWithRepoCount() async throws {
        let db = try makeDB()
        let acct1 = try insertAccount(db, login: "alpha")
        let acct2 = try insertAccount(db, login: "bravo")

        _ = try await insertRepo(db, accountId: acct1.id, name: "RepoA", sortOrder: 0)
        _ = try await insertRepo(db, accountId: acct1.id, name: "RepoB", sortOrder: 1)
        _ = try await insertRepo(db, accountId: acct1.id, name: "RepoC", sortOrder: 2)

        let vm = makeVM(db: db)
        await vm.refresh()

        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.rows.count, 2)

        // Rows are ordered by the DAO (`ORDER BY login, host`) — alpha first.
        let alphaRow = try XCTUnwrap(vm.rows.first { $0.account.id == acct1.id })
        XCTAssertEqual(alphaRow.repoCount, 3)
        let bravoRow = try XCTUnwrap(vm.rows.first { $0.account.id == acct2.id })
        XCTAssertEqual(bravoRow.repoCount, 0)
    }

    func test_refresh_marksPrimary() async throws {
        let db = try makeDB()
        let acct1 = try insertAccount(db, login: "alpha")
        let acct2 = try insertAccount(db, login: "bravo")

        let vm = makeVM(db: db, primary: acct1.id)
        await vm.refresh()

        let alphaRow = try XCTUnwrap(vm.rows.first { $0.account.id == acct1.id })
        XCTAssertTrue(alphaRow.isPrimary)
        let bravoRow = try XCTUnwrap(vm.rows.first { $0.account.id == acct2.id })
        XCTAssertFalse(bravoRow.isPrimary)
    }

    func test_refresh_attachesLastUsed_fromAPI() async throws {
        let db = try makeDB()
        let acct1 = try insertAccount(db, login: "alpha")
        let acct2 = try insertAccount(db, login: "bravo")

        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let tracker = StubAccountUsageTracker([acct1.id: stamp])
        let vm = makeVM(db: db, api: tracker)
        await vm.refresh()

        let alphaRow = try XCTUnwrap(vm.rows.first { $0.account.id == acct1.id })
        XCTAssertEqual(alphaRow.lastUsed, stamp)
        let bravoRow = try XCTUnwrap(vm.rows.first { $0.account.id == acct2.id })
        XCTAssertNil(bravoRow.lastUsed)
    }

    func test_refresh_attachesScopes() async throws {
        let db = try makeDB()
        let acct1 = try insertAccount(db, login: "alpha")
        let acct2 = try insertAccount(db, login: "bravo")

        let vm = makeVM(
            db: db,
            scopes: [acct1.id: ["repo", "read:org"]]
        )
        await vm.refresh()

        let alphaRow = try XCTUnwrap(vm.rows.first { $0.account.id == acct1.id })
        XCTAssertEqual(alphaRow.scopes, ["repo", "read:org"])
        let bravoRow = try XCTUnwrap(vm.rows.first { $0.account.id == acct2.id })
        XCTAssertEqual(bravoRow.scopes, [])
    }
}
