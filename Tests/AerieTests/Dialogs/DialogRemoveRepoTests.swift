import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for `DialogRemoveRepo` — the neutral-toned remove
/// confirmation. Single test covers the only visual permutation; the
/// "Will delete: nothing on disk" KV row is the dialog's load-bearing copy.
final class DialogRemoveRepoTests: XCTestCase {
    private func host<V: View>(_ view: V) -> NSHostingView<some View> {
        let frame = ZStack {
            Backdrop()
            view
        }
        .frame(width: 1240, height: 880)
        return NSHostingView(rootView: frame)
    }

    func test_dialogRemoveRepo() {
        let repo = Repository(
            id: UUID(uuidString: "44444444-0000-0000-0000-000000000001")!,
            name: "Aerie",
            localPath: URL(fileURLWithPath: "/Users/dev/work/aerie"),
            githubOwner: "carlos-li",
            githubRepo: "aerie",
            defaultBranch: "main",
            primaryAccountId: UUID(uuidString: "44444444-0000-0000-0000-000000000002")!,
            sortOrder: 0,
            hidden: false
        )
        let view = DialogRemoveRepo(repo: repo, onConfirm: { }, onCancel: { })
        assertSnapshot(of: host(view), as: .image(size: CGSize(width: 1240, height: 880)))
    }
}
