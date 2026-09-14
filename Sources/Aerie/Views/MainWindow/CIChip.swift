import SwiftUI

/// A pill-style chip that summarises the CI status of a pull request.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` `CIStatus(...)` — a
/// tone-coloured `StatusPill` with a leading dot and a `CI …` label. MARK III
/// tones: green passing, crimson failing, and arc cyan while checks are still
/// running (in-progress work is the one thing allowed to glow cyan).
struct CIChip: View {
    let state: CIState

    var body: some View {
        StatusPill(text: label, tone: tone, showsDot: true)
    }

    private var tone: StatusPill.Tone {
        switch state {
        case .success: return .ok
        case .failure: return .err
        case .pending: return .arc
        case .none:    return .muted
        }
    }

    private var label: String {
        switch state {
        case .success: return "CI passing"
        case .failure: return "CI failing"
        case .pending: return "CI pending"
        case .none:    return "No checks"
        }
    }
}
