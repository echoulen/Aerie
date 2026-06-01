import SwiftUI

/// A pill-style chip that summarises the review status of a pull request.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `ReviewStatus(...)` —
/// a tone-coloured `StatusPill` (no dot): an `ok` "Approved", an `err`
/// "Changes requested", or a neutral "Review requested".
struct ReviewChip: View {
    let state: ReviewState

    var body: some View {
        StatusPill(text: label, tone: tone)
    }

    private var tone: StatusPill.Tone {
        switch state {
        case .approved:         return .ok
        case .changesRequested: return .err
        case .reviewRequired:   return .neutral
        }
    }

    private var label: String {
        switch state {
        case .approved:         return "Approved"
        case .changesRequested: return "Changes requested"
        case .reviewRequired:   return "Review requested"
        }
    }
}
