import Foundation
import Observation
import CoreGraphics

/// View model for Settings → Appearance.
///
/// Backs the interface-zoom control (design `appearance.jsx`): a five-stop
/// "display size" stepper that scales the whole UI the way ⌘+ zooms a
/// browser. This VM owns the *selection* — the active stop — and persists it
/// via `SettingsDAO` under `appearance.zoom_pct`. A single shared instance is
/// the source of truth: the Settings screen + keyboard shortcuts (⌘+/⌘−/⌘0)
/// mutate it, and `AerieApp` reads `scale` to zoom the main window live.
@Observable
final class AppearanceViewModel {
    /// One stop on the display-size stepper. `pct` is the interface zoom
    /// percentage; `label` is the human word shown under the tick.
    struct ZoomStop: Equatable {
        let pct: Int
        let label: String
    }

    /// The five stops, matching the design exactly.
    static let stops: [ZoomStop] = [
        ZoomStop(pct: 85,  label: "Smaller"),
        ZoomStop(pct: 92,  label: "Small"),
        ZoomStop(pct: 100, label: "Default"),
        ZoomStop(pct: 110, label: "Large"),
        ZoomStop(pct: 125, label: "Larger"),
    ]

    /// Index of the 100% stop — the default selection.
    static let defaultIndex = 2
    static let defaultPct = 100
    static let storageKey = "appearance.zoom_pct"

    private(set) var activeIndex: Int = defaultIndex

    /// The zoom percentage of the currently-selected stop.
    var zoomPct: Int { Self.stops[activeIndex].pct }

    /// The geometric scale factor for the active stop (e.g. 1.25 at 125%).
    /// `AerieApp.InterfaceZoom` applies this to the main window via
    /// `scaleEffect`, which is how the interface actually zooms — macOS SwiftUI
    /// won't scale fonts through Dynamic Type, so a geometric scale is used.
    var scale: CGFloat { CGFloat(zoomPct) / 100.0 }

    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// Loads the persisted stop. An absent or unrecognised value falls back
    /// to 100% (we only ever persist one of the five known stops, so an
    /// off-list value means legacy/garbage and is ignored).
    func refresh() async {
        if let pct = try? await db.settings.getInt(Self.storageKey),
           let idx = Self.stops.firstIndex(where: { $0.pct == pct }) {
            activeIndex = idx
        } else {
            activeIndex = Self.defaultIndex
        }
    }

    /// Selects a stop by index (clamped to the valid range) and persists it.
    func select(_ index: Int) async {
        activeIndex = min(max(index, 0), Self.stops.count - 1)
        try? await db.settings.setInt(Self.storageKey, zoomPct)
    }

    /// ⌘+ : move one stop larger (clamped at the top).
    func zoomIn() async { await select(activeIndex + 1) }

    /// ⌘− : move one stop smaller (clamped at the bottom).
    func zoomOut() async { await select(activeIndex - 1) }

    /// ⌘0 : return to 100%.
    func reset() async { await select(Self.defaultIndex) }
}
