import Foundation
import Observation

/// View model for Settings → AI Review: the editable guidance sections of the
/// review prompt (`AIReviewGuidance`), one per tab.
///
/// Edits save 600ms after the last keystroke. Text equal to the built-in
/// default — or blank — clears the stored key, so the page reads "default"
/// and a future change to the built-in text still reaches the user.
@MainActor
@Observable
final class AIReviewGuidanceViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case firstPass, followUp
        var id: String { rawValue }
        var title: String { self == .firstPass ? "First pass" : "Follow-up" }
        var key: String { self == .firstPass ? AIReviewGuidance.firstPassKey : AIReviewGuidance.followUpKey }
        var defaultText: String { self == .firstPass ? AIReviewGuidance.defaultFirstPass : AIReviewGuidance.defaultFollowUp }
    }

    var tab: Tab = .firstPass
    private(set) var texts: [Tab: String] = [
        .firstPass: AIReviewGuidance.defaultFirstPass,
        .followUp: AIReviewGuidance.defaultFollowUp,
    ]

    private let db: AppDatabase
    private let debounce: Duration
    private var pendingSaves: [Tab: Task<Void, Never>] = [:]

    init(db: AppDatabase, debounce: Duration = .milliseconds(600)) {
        self.db = db
        self.debounce = debounce
    }

    func refresh() async {
        for tab in Tab.allCases where pendingSaves[tab] == nil {
            let stored = (try? await db.settings.getString(tab.key)) ?? nil
            texts[tab] = stored ?? tab.defaultText
        }
    }

    func text(_ tab: Tab) -> String { texts[tab] ?? tab.defaultText }

    /// True when `tab`'s text differs from the built-in default (what the
    /// "custom" / "default" pill shows).
    func isCustom(_ tab: Tab) -> Bool { Self.storedValue(text(tab), for: tab) != nil }

    /// Updates the text and schedules a debounced save.
    func setText(_ text: String, for tab: Tab) {
        texts[tab] = text
        pendingSaves[tab]?.cancel()
        pendingSaves[tab] = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.persist(tab)
        }
    }

    /// Restores the built-in text and clears the stored value immediately.
    func reset(_ tab: Tab) async {
        pendingSaves[tab]?.cancel()
        texts[tab] = tab.defaultText
        await persist(tab)
    }

    /// Writes any pending edits now (e.g. when the page goes away).
    func flush() async {
        for tab in Tab.allCases where pendingSaves[tab] != nil {
            pendingSaves[tab]?.cancel()
            await persist(tab)
        }
    }

    private func persist(_ tab: Tab) async {
        pendingSaves[tab] = nil
        if let value = Self.storedValue(text(tab), for: tab) {
            try? await db.settings.setString(tab.key, value)
        } else {
            try? await db.settings.delete(tab.key)
        }
    }

    /// What to store for `text`: nil (use the default) when it's blank or
    /// identical to the built-in text.
    static func storedValue(_ text: String, for tab: Tab) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != tab.defaultText else { return nil }
        return text
    }

    // MARK: Prompt preview

    /// The fixed prompt text before the editable section, with placeholders
    /// standing in for the PR — rendered by the same code that builds the real
    /// prompt so the page can't drift from it.
    func lockedHead(_ tab: Tab) -> String {
        let header = ClaudeReviewPrompt.header(
            owner: "{{OWNER}}", repo: "{{REPO}}", number: 0,
            title: "{{TITLE}}", author: "{{AUTHOR}}", sourceBranch: "{{SOURCE_BRANCH}}")
            .replacingOccurrences(of: "PR #0", with: "PR #{{NUMBER}}")
        switch tab {
        case .firstPass:
            return header
        case .followUp:
            return """
            \(header)

            {{FIRST-PASS GUIDANCE}}

            Diff:
            {{DIFF}}

            FOLLOW-UP REVIEW. You reviewed this PR before …
            {{PREVIOUS REVIEW · NEW COMMITS · REPLIES}}
            """
        }
    }

    /// The fixed prompt text after the editable section.
    func lockedTail(_ tab: Tab) -> String {
        switch tab {
        case .firstPass:
            return """
            Diff:
            {{DIFF}}
            {{FOLLOW-UP SECTION · re-reviews only}}

            \(ClaudeReviewPrompt.contract(followUp: false))
            """
        case .followUp:
            return """
            \(ClaudeReviewPrompt.replyGuard)

            \(ClaudeReviewPrompt.contract(followUp: true))
            """
        }
    }

    /// Rough size of the fixed and editable parts, excluding the diff and PR
    /// replies (≈ 4 characters per token).
    func approxTokens(_ tab: Tab) -> Int {
        (lockedHead(tab).count + text(tab).count + lockedTail(tab).count) / 4
    }
}
