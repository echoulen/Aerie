import XCTest
import SwiftUI
import SnapshotTesting
@testable import Aerie

/// Snapshot coverage for the four atomic chip components introduced in
/// Phase 9.2: CIChip, ReviewChip, BranchTag, DeltaView. Each chip is rendered
/// against the standard backdrop colour so the snapshot stays comparable
/// across runs.
final class AtomicChipsTests: XCTestCase {
    private func host<V: View>(_ view: V, size: CGSize = CGSize(width: 220, height: 60)) -> NSHostingView<some View> {
        let wrapped = ZStack {
            AerieColor.backdrop1
            view.padding(12)
        }
        .frame(width: size.width, height: size.height)
        return NSHostingView(rootView: wrapped)
    }

    // MARK: - CIChip

    func test_ciChip_success() {
        assertSnapshot(
            of: host(CIChip(state: .success)),
            as: .image(size: CGSize(width: 220, height: 60))
        )
    }

    func test_ciChip_failure() {
        assertSnapshot(
            of: host(CIChip(state: .failure)),
            as: .image(size: CGSize(width: 220, height: 60))
        )
    }

    func test_ciChip_pending() {
        assertSnapshot(
            of: host(CIChip(state: .pending)),
            as: .image(size: CGSize(width: 220, height: 60))
        )
    }

    func test_ciChip_none() {
        assertSnapshot(
            of: host(CIChip(state: .none)),
            as: .image(size: CGSize(width: 220, height: 60))
        )
    }

    // MARK: - ReviewChip

    func test_reviewChip_approved() {
        assertSnapshot(
            of: host(ReviewChip(state: .approved)),
            as: .image(size: CGSize(width: 260, height: 60))
        )
    }

    func test_reviewChip_changesRequested() {
        assertSnapshot(
            of: host(ReviewChip(state: .changesRequested)),
            as: .image(size: CGSize(width: 260, height: 60))
        )
    }

    func test_reviewChip_reviewRequired() {
        assertSnapshot(
            of: host(ReviewChip(state: .reviewRequired)),
            as: .image(size: CGSize(width: 260, height: 60))
        )
    }

    // MARK: - BranchTag

    func test_branchTag_notCurrent() {
        assertSnapshot(
            of: host(BranchTag(name: "feat/phase9-prs-view", isCurrent: false)),
            as: .image(size: CGSize(width: 280, height: 60))
        )
    }

    func test_branchTag_current() {
        assertSnapshot(
            of: host(BranchTag(name: "feat/phase9-prs-view", isCurrent: true)),
            as: .image(size: CGSize(width: 280, height: 60))
        )
    }

    // MARK: - DeltaView

    /// All-zero delta should collapse to nothing on-screen.
    func test_deltaView_allZeroHides() {
        assertSnapshot(
            of: host(DeltaView(ahead: 0, behind: 0, unpushed: 0)),
            as: .image(size: CGSize(width: 200, height: 50))
        )
    }

    func test_deltaView_mixed() {
        assertSnapshot(
            of: host(DeltaView(ahead: 3, behind: 1, unpushed: 2)),
            as: .image(size: CGSize(width: 200, height: 50))
        )
    }

    func test_deltaView_aheadOnly() {
        assertSnapshot(
            of: host(DeltaView(ahead: 5, behind: 0, unpushed: 0)),
            as: .image(size: CGSize(width: 200, height: 50))
        )
    }
}
