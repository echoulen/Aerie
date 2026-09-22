import Foundation

/// The user-owned part of the AI Review prompt: what counts as a major
/// problem (first pass) and how to judge previously raised issues (follow-up).
///
/// Everything else in the prompt — the PR context header, the diff, the
/// follow-up context, the injection guard and the JSON verdict contract —
/// stays fixed in `ClaudeReviewPrompt`, because Aerie parses the reply and a
/// free-form prompt could break the verdict.
struct AIReviewGuidance: Sendable, Equatable {
    var firstPass: String
    var followUp: String

    static let firstPassKey = "ai.reviewGuidance"
    static let followUpKey = "ai.followUpGuidance"

    static let defaultFirstPass = """
        Review the diff below for MAJOR problems only: correctness bugs, security \
        vulnerabilities, breaking changes, or data loss. Style nits and minor \
        preferences are NOT major.
        """

    static let defaultFollowUp = """
        For EACH major issue your previous review raised, report it in "previous" with a status:
        - "fixed": the current diff resolves it.
        - "justified": not changed, but a reply explains convincingly why it isn't a \
        problem (e.g. the path can't be reached, it's intentional and safe, it's handled \
        elsewhere). Accept it and do NOT raise it again.
        - "open": neither fixed nor convincingly explained. Say in "note" why the \
        explanation, if any, doesn't hold.
        New major problems in the current diff still count.
        """

    static let `default` = AIReviewGuidance(firstPass: defaultFirstPass, followUp: defaultFollowUp)

    /// Stored values win; an absent or blank value falls back to the built-in
    /// text so an emptied field never sends Claude a prompt with no guidance.
    static func resolve(firstPass: String?, followUp: String?) -> AIReviewGuidance {
        AIReviewGuidance(
            firstPass: nonBlank(firstPass) ?? defaultFirstPass,
            followUp: nonBlank(followUp) ?? defaultFollowUp)
    }

    private static func nonBlank(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}
