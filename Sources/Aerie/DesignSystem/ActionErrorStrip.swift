import SwiftUI

/// Inline error strip rendered below a row after a background row action
/// fails (merge conflict, network error, …) — the shared visual home for
/// every `PRActionStore`/`RepoActionStore` failure. Originally
/// `WorktreeRail`'s bespoke `WorktreeMergeErrorStrip`; generalized so
/// `PRCard`, `RepoCard`, and `WorktreeRail` all render failures the same way
/// instead of falling back to a modal.
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
                .buttonStyle(.plain)
                .aerieFont(AerieFont.custom(.sans, size: 11.5).weight(.medium))
                .foregroundStyle(AerieColor.text2)
            DismissButton(action: onDismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AerieColor.err.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AerieColor.err.opacity(0.4), lineWidth: 1))
        .padding(.bottom, 9)
    }
}

/// `.wt-err-dismiss` — a quiet ghost control that clears an `ActionErrorStrip`.
/// Moved here from `WorktreeRail` (where it was `private`) since it's now
/// shared across every row type that can show one of these strips.
struct DismissButton: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Dismiss")
                .font(.custom(AerieFont.sans, size: 11.5).weight(.medium))
                .foregroundStyle(hovering ? AerieColor.text1 : AerieColor.text3)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? AerieColor.glass3 : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(hovering ? AerieColor.glassLine2 : AerieColor.glassLine, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
