import XCTest
@testable import Aerie

@MainActor
final class ToastManagerTests: XCTestCase {
    func test_toastManager_pushAndDismiss() async {
        let mgr = ToastManager(autoDismissSeconds: 60.0)
        let item = ToastItem(title: "Merged PR #42", tone: .success)
        mgr.push(item)
        XCTAssertEqual(mgr.items.count, 1)
        mgr.dismiss(item.id)
        XCTAssertEqual(mgr.items.count, 0)
    }

    func test_toastManager_capsAtMaxVisible() {
        let mgr = ToastManager(autoDismissSeconds: 60.0)
        for i in 0..<5 {
            mgr.push(ToastItem(title: "n=\(i)", tone: .info))
        }
        XCTAssertEqual(mgr.items.count, ToastManager.maxVisible)
    }

    func test_toastManager_pushOrdering_newestFirst() {
        let mgr = ToastManager(autoDismissSeconds: 60.0)
        let a = ToastItem(title: "A", tone: .info)
        let b = ToastItem(title: "B", tone: .info)
        mgr.push(a)
        mgr.push(b)
        // Newest at index 0.
        XCTAssertEqual(mgr.items.first?.id, b.id)
        XCTAssertEqual(mgr.items.last?.id, a.id)
    }

    func test_toastManager_capDropsOldest() {
        let mgr = ToastManager(autoDismissSeconds: 60.0)
        let first = ToastItem(title: "first", tone: .info)
        mgr.push(first)
        for i in 0..<ToastManager.maxVisible {
            mgr.push(ToastItem(title: "later \(i)", tone: .info))
        }
        // After maxVisible + 1 pushes, the original oldest must be gone.
        XCTAssertFalse(mgr.items.contains { $0.id == first.id })
        XCTAssertEqual(mgr.items.count, ToastManager.maxVisible)
    }
}
