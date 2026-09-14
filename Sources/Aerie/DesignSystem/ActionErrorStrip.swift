import SwiftUI

/// Inline error strip rendered below a row after a background row action
/// fails (merge conflict, network error, …) — the shared visual home for
/// every `PRActionStore`/`RepoActionStore` failure. `PRCard`, `RepoCard`, and
/// `WorktreeRail` all render failures the same way instead of falling back to
/// a modal.
///
/// MARK III: a crimson-washed square plate with a hot crimson strut on the
/// leading edge; Retry / Dismiss are small bevelled HUD keys.
struct ActionErrorStrip: View {
    let message: String
    var onRetry: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(AerieColor.dangerText)
                .padding(.top, 1)
            Text(message)
                .aerieFont(AerieFont.custom(.sans, size: 12))
                .foregroundStyle(AerieColor.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Retry", action: onRetry)
                .buttonStyle(.hud(.standard, size: .small))
            DismissButton(action: onDismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .crimsonStrip()
        .padding(.bottom, 9)
    }
}

/// `.wt-err-dismiss` — a quiet ghost HUD key that clears an `ActionErrorStrip`.
/// Shared across every row type that can show one of these strips.
struct DismissButton: View {
    var action: () -> Void

    var body: some View {
        Button("Dismiss", action: action)
            .buttonStyle(.hud(.ghost, size: .small))
    }
}
