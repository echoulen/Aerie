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
}
