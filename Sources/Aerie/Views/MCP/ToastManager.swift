import SwiftUI
import Observation

/// One toast in the bottom-right MCP toast stack. Created by the integration
/// layer when a write tool finishes (success or failure) and pushed onto the
/// shared `ToastManager`.
///
/// `requestJSON` + `responseJSON` are carried alongside the visible fields so
/// the "View request" action can open `ViewRequestModal` without re-fetching.
struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String?
    let tone: Tone
    let requestJSON: String?
    let responseJSON: String?

    enum Tone: Equatable { case success, error, info }

    init(
        title: String,
        subtitle: String? = nil,
        tone: Tone = .info,
        requestJSON: String? = nil,
        responseJSON: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.requestJSON = requestJSON
        self.responseJSON = responseJSON
    }
}

/// Owns the live toast stack: holds an ordered list (newest first), caps it
/// at `maxVisible`, and auto-dismisses each toast after `autoDismissSeconds`.
/// Hovering a toast pauses dismissal; un-hovering re-schedules it.
///
/// Tests inject a shorter `autoDismissSeconds` so the dismiss path can run
/// in real time without a long sleep. The cap + ordering tests don't need
/// any waits.
@Observable
@MainActor
final class ToastManager {
    private(set) var items: [ToastItem] = []
    static let maxVisible = 3

    /// Auto-dismiss interval. Mutable so tests can shrink it.
    var autoDismissSeconds: TimeInterval

    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private var hovered: Set<UUID> = []

    init(autoDismissSeconds: TimeInterval = 6.0) {
        self.autoDismissSeconds = autoDismissSeconds
    }

    /// Insert at the front (newest-first). If the stack exceeds `maxVisible`,
    /// drop the oldest (last) entry and cancel its pending dismiss task.
    func push(_ item: ToastItem) {
        items.insert(item, at: 0)
        if items.count > Self.maxVisible {
            let removed = items.removeLast()
            cancelDismiss(removed.id)
        }
        scheduleDismiss(item.id)
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        cancelDismiss(id)
    }

    /// Called by the toast view's `onHover`. Pauses dismissal while hovered;
    /// reschedules it on hover-out.
    func setHovered(_ id: UUID, _ value: Bool) {
        if value {
            hovered.insert(id)
            cancelDismiss(id)
        } else {
            hovered.remove(id)
            if items.contains(where: { $0.id == id }) {
                scheduleDismiss(id)
            }
        }
    }

    private func scheduleDismiss(_ id: UUID) {
        cancelDismiss(id)
        let seconds = autoDismissSeconds
        dismissTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismiss(id) }
        }
    }

    private func cancelDismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
    }
}
