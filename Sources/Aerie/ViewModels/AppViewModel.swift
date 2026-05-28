import SwiftUI
import Observation

/// The two top-level destinations selectable in the main window's titlebar.
enum MainTab: String, Equatable, CaseIterable {
    case prs, repos
}

/// Shared state owner for the main window shell.
///
/// `nextTickInSeconds` is the integration surface for `LiveIndicator`. Phase 8
/// doesn't drive it from a real scheduler yet — tests pass values directly. A
/// later phase wires it to `PollingScheduler`.
@Observable
final class AppViewModel {
    var activeTab: MainTab
    /// Seconds until the next polling tick. `nil` means scheduler isn't running.
    var nextTickInSeconds: Int?

    init(activeTab: MainTab = .prs, nextTickInSeconds: Int? = nil) {
        self.activeTab = activeTab
        self.nextTickInSeconds = nextTickInSeconds
    }
}
