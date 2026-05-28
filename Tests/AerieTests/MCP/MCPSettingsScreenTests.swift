import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

@MainActor
final class MCPSettingsScreenTests: XCTestCase {
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

    /// Deterministic dates for the relative-time formatting in activity rows.
    /// We anchor everything within 30s of "now" so the row labels never tip
    /// across the minute/hour/day boundary between snapshot recording and
    /// playback.
    private func seedActivity(_ db: AppDatabase) async throws {
        let now = Date()
        let records: [MCPActivityRecord] = [
            MCPActivityRecord(
                id: nil, at: now.addingTimeInterval(-5),
                agentId: "cc-session-7f2a", tool: "aerie_merge_pr",
                target: "owner/repo · #1234", isWrite: true, ok: true,
                errorMessage: nil,
                requestJSON: #"{"method":"tools/call"}"#,
                responseJSON: #"{"result":{"ok":true}}"#
            ),
            MCPActivityRecord(
                id: nil, at: now.addingTimeInterval(-12),
                agentId: "cc-session-7f2a", tool: "aerie_list_open_prs",
                target: nil, isWrite: false, ok: true,
                errorMessage: nil,
                requestJSON: #"{"method":"tools/call"}"#,
                responseJSON: #"{"result":[]}"#
            ),
            MCPActivityRecord(
                id: nil, at: now.addingTimeInterval(-20),
                agentId: "unknown", tool: "aerie_hard_reset_to_default",
                target: "owner/other · main", isWrite: true, ok: false,
                errorMessage: "merge conflict",
                requestJSON: #"{"method":"tools/call"}"#,
                responseJSON: #"{"error":{"code":-32001}}"#
            ),
        ]
        for r in records {
            try await db.mcpActivity.insert(r)
        }
    }

    func test_mcpSettingsScreen_running() async throws {
        let db = try makeDB()
        try await seedActivity(db)
        try await db.settings.setBool("mcp.auto_register_claude_code", true)

        let endpoint = URL(string: "http://127.0.0.1:47823/mcp")!
        let stubStatus = MCPSettingsViewModel.ServerStatus(
            running: true,
            pid: 81421,
            uptimeSeconds: 60 * 60 * 2 + 60 * 14, // 2h 14m
            endpoint: endpoint
        )

        let vm = MCPSettingsViewModel(
            db: db,
            discoveryFilePath: URL(fileURLWithPath: "/Users/example/Library/Application Support/Aerie/mcp.json"),
            serverStatus: { stubStatus },
            tokenProvider: { "aer_1234567890abcdef" },
            rotateToken: { },
            runConfigUpsert: { },
            runConfigRemove: { }
        )
        await vm.refresh()

        XCTAssertEqual(vm.status.running, true)
        XCTAssertEqual(vm.recentActivity.count, 3)
        XCTAssertTrue(vm.autoRegisterOn)

        let view = ZStack {
            Backdrop()
            MCPSettingsScreen(viewModel: vm)
        }
        .frame(width: 820, height: 760)
        let host = NSHostingView(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 820, height: 760)))
    }
}
