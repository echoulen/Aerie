import Foundation

/// The Claude model used to run AI Review and Create Pull Request. A fixed,
/// closed list — no free-text entry, no "follow CLI default" option; a
/// specific model is always selected and always passed to `claude` via
/// `--model`. See docs/superpowers/specs/2026-07-10-ai-model-setting-design.md.
enum ClaudeModel: String, CaseIterable, Identifiable, Sendable, Equatable {
    case sonnet5 = "claude-sonnet-5"
    case opus48 = "claude-opus-4-8"
    case haiku45 = "claude-haiku-4-5-20251001"
    case fable5 = "claude-fable-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonnet5: return "Sonnet 5"
        case .opus48: return "Opus 4.8"
        case .haiku45: return "Haiku 4.5"
        case .fable5: return "Fable 5"
        }
    }

    /// Used whenever no model has been persisted yet, or the persisted value
    /// no longer matches a known case.
    static let `default`: ClaudeModel = .sonnet5
}
