import Foundation
import Observation

/// View model for Settings → Pull Requests.
///
/// Holds the PR-publish prompt template. The stored value in `settings`
/// (`pr_publish.template`) exists ONLY when the user has customised the
/// template — absent (or blank, or identical to the default) means "use the
/// built-in default", so shipped template improvements reach non-customising
/// users automatically.
///
/// Saving is debounced (~500 ms) as the user types — Settings has no Save
/// buttons anywhere, and a half-typed template is harmless: it only matters
/// at the moment a publish run starts.
@MainActor
@Observable
final class PRPublishViewModel {
    static let settingsKey = "pr_publish.template"

    private(set) var template: String = DefaultPRPublishTemplate.text
    private(set) var isCustom: Bool = false

    private let db: AppDatabase
    private let debounceNanos: UInt64
    private var saveTask: Task<Void, Never>?

    init(db: AppDatabase, debounceMilliseconds: UInt64 = 500) {
        self.db = db
        self.debounceNanos = debounceMilliseconds * 1_000_000
    }

    /// Loads the stored custom template, falling back to the built-in default.
    func refresh() async {
        let stored = (try? await db.settings.getString(Self.settingsKey)) ?? nil
        if let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            template = stored
            isCustom = true
        } else {
            template = DefaultPRPublishTemplate.text
            isCustom = false
        }
    }

    /// Updates the in-memory template immediately and schedules a debounced
    /// persist. Text identical to the default (or blank) is stored as
    /// key-absent, not as a copy — see the class doc.
    func setTemplate(_ text: String) {
        template = text
        let blank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isCustom = !blank && text != DefaultPRPublishTemplate.text
        saveTask?.cancel()
        saveTask = Task { [db, debounceNanos] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            if blank || text == DefaultPRPublishTemplate.text {
                try? await db.settings.delete(Self.settingsKey)
            } else {
                try? await db.settings.setString(Self.settingsKey, text)
            }
        }
    }

    /// Restores the built-in default and removes the stored custom template.
    func resetToDefault() async {
        saveTask?.cancel()
        template = DefaultPRPublishTemplate.text
        isCustom = false
        try? await db.settings.delete(Self.settingsKey)
    }
}
