import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the `AddRepoSheet` empty state. Phase 13.5
/// adds coverage for the detected state in a separate test.
final class AddRepoSheetTests: XCTestCase {
    private func host(_ vm: AddRepoSheetViewModel) -> NSHostingView<some View> {
        let view = ZStack {
            Backdrop()
            AddRepoSheet(viewModel: vm, onCancel: { }, onAdd: { _, _ in })
        }
        .frame(width: 720, height: 600)
        return NSHostingView(rootView: view)
    }

    func test_addRepoSheet_empty_noCandidates() {
        let vm = AddRepoSheetViewModel()
        assertSnapshot(of: host(vm), as: .image(size: CGSize(width: 720, height: 600)))
    }

    func test_addRepoSheet_empty_withCandidates() {
        let vm = AddRepoSheetViewModel()
        vm.setCandidates([
            RepoCandidate(
                url: URL(fileURLWithPath: "/Users/dev/work/aerie"),
                lastTouched: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            RepoCandidate(
                url: URL(fileURLWithPath: "/Users/dev/work/bridge"),
                lastTouched: Date(timeIntervalSince1970: 1_699_900_000)
            ),
        ])
        assertSnapshot(of: host(vm), as: .image(size: CGSize(width: 720, height: 600)))
    }

    // MARK: - Account selection / probe logic

    private func makeDetected(suggested: UUID?) -> DetectedRepo {
        DetectedRepo(
            url: URL(fileURLWithPath: "/opt/repos/ioe-portal-ui"),
            githubOwner: "nextDriveIoE",
            githubRepo: "ioe-portal-ui",
            host: "github.com",
            defaultBranch: "main",
            currentBranch: "main",
            isDirty: false,
            suggestedAccountId: suggested
        )
    }

    func test_applyDetected_defaultsSelectionToSuggestion_whenProbeFindsNothing() async {
        let suggested = UUID()
        let vm = AddRepoSheetViewModel()
        vm.resolveAccount = { _ in nil }   // probe inconclusive

        await vm.applyDetected(makeDetected(suggested: suggested))

        XCTAssertEqual(vm.selectedAccountId, suggested)
    }

    func test_applyDetected_prefersProbeResult_overHostSuggestion() async {
        // The host heuristic suggests the wrong (first same-host) account; the
        // API probe finds the account that can actually see the org repo and
        // that must become the selection.
        let suggested = UUID()
        let probed = UUID()
        let vm = AddRepoSheetViewModel()
        vm.resolveAccount = { _ in probed }

        await vm.applyDetected(makeDetected(suggested: suggested))

        XCTAssertEqual(vm.selectedAccountId, probed)
    }

    func test_selectAccount_overridesSelection() async {
        let suggested = UUID()
        let manual = UUID()
        let vm = AddRepoSheetViewModel()
        vm.resolveAccount = { _ in nil }
        await vm.applyDetected(makeDetected(suggested: suggested))

        vm.selectAccount(manual)

        XCTAssertEqual(vm.selectedAccountId, manual)
    }

    func test_addRepoSheet_detected() {
        let vm = AddRepoSheetViewModel()
        let suggested = UUID(uuidString: "12345678-0000-0000-0000-000000000000")!
        let other = UUID(uuidString: "87654321-0000-0000-0000-000000000000")!
        vm.accounts = [
            GitHubAccount(id: suggested, login: "carlos-li", host: "github.com"),
            GitHubAccount(id: other, login: "work-acct", host: "github.com"),
        ]
        let detected = DetectedRepo(
            url: URL(fileURLWithPath: "/opt/repos/aerie"),
            githubOwner: "carlos-li",
            githubRepo: "aerie",
            host: "github.com",
            defaultBranch: "main",
            currentBranch: "feat/phase13",
            isDirty: true,
            suggestedAccountId: suggested
        )
        // Seed the detected state + selection so the snapshot exercises the
        // account picker (selected row marked). `injectStateForTesting` sets the
        // state; `selectAccount` mirrors what the probe/user would set.
        vm.injectStateForTesting(.detected(detected))
        vm.selectAccount(suggested)
        assertSnapshot(of: host(vm), as: .image(size: CGSize(width: 720, height: 600)))
    }
}
