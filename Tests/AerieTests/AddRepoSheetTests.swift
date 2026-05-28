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
            AddRepoSheet(viewModel: vm, onCancel: { }, onAdd: { _ in })
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

    func test_addRepoSheet_detected() {
        let vm = AddRepoSheetViewModel()
        let suggested = UUID(uuidString: "12345678-0000-0000-0000-000000000000")!
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
        // Inject the detected state directly by routing through the VM API.
        // `runDetection` writes the state, but for a deterministic snapshot
        // we set it via the chooseFolder/runDetection path with a stub
        // detector. Simpler: call into a private path through chooseFolder
        // is not feasible — fall back to seeding state via a helper.
        vm.injectStateForTesting(.detected(detected))
        assertSnapshot(of: host(vm), as: .image(size: CGSize(width: 720, height: 600)))
    }
}
