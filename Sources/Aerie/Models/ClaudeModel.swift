import Foundation

/// The Claude model used to run AI Review. A fixed,
/// closed list — no free-text entry, no "follow CLI default" option; a
/// specific model is always selected and always passed to `claude` via
/// `--model`. See docs/superpowers/specs/2026-07-10-ai-model-setting-design.md.
enum ClaudeModel: String, CaseIterable, Identifiable, Sendable, Equatable {
    case sonnet5 = "claude-sonnet-5"
    case opus55 = "claude-opus-5-5"
    case haiku45 = "claude-haiku-4-5-20251001"
    case fable51 = "claude-fable-5-1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonnet5: return "Sonnet 5"
        case .opus55: return "Opus 5.5"
        case .haiku45: return "Haiku 4.5"
        case .fable51: return "Fable 5.1"
        }
    }

    /// Used whenever no model has been persisted yet, or the persisted value
    /// no longer matches a known case.
    static let `default`: ClaudeModel = .sonnet5

    /// Resolves a persisted `ai.model` value. A model this list has since
    /// replaced carries over to its successor, so an upgrade keeps the user's
    /// choice instead of silently dropping back to `default`.
    static func resolve(stored: String?) -> ClaudeModel {
        guard let stored else { return .default }
        if let model = ClaudeModel(rawValue: stored) { return model }
        switch stored {
        case "claude-opus-5", "claude-opus-4-8": return .opus55
        case "claude-fable-5": return .fable51
        default: return .default
        }
    }
}
