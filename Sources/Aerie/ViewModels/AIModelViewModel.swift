import Foundation
import Observation

/// View model for Settings → AI Model.
///
/// Holds the Claude model used by both AI Review and Create Pull Request.
/// Always resolves to a concrete `ClaudeModel` — there is no "unset" state;
/// an absent or unrecognised stored value falls back to `ClaudeModel.default`
/// (Sonnet 5). Persisted via `SettingsDAO` under `ai.model`.
@MainActor
@Observable
final class AIModelViewModel {
    static let settingsKey = "ai.model"

    private(set) var selected: ClaudeModel = .default

    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// Loads the persisted model. An absent or unrecognised value falls back
    /// to `ClaudeModel.default`.
    func refresh() async {
        let stored = (try? await db.settings.getString(Self.settingsKey)) ?? nil
        selected = stored.flatMap(ClaudeModel.init(rawValue:)) ?? .default
    }

    /// Selects a model and persists it immediately (no debounce — this is a
    /// discrete picker choice, not free text).
    func setModel(_ model: ClaudeModel) async {
        selected = model
        try? await db.settings.setString(Self.settingsKey, model.rawValue)
    }
}
