import SwiftUI

/// Inline error strip rendered below a row after a background row action
/// fails (merge conflict, network error, …) — the shared visual home for
/// every `PRActionStore`/`RepoActionStore` failure. `PRCard`, `RepoCard`, and
/// `WorktreeRail` all render failures the same way instead of falling back to
/// a modal.
///
/// Visual contract: `styles.css` `.wt-merge-error` — 2pt radius, crimson-line
/// border on a crimson-soft wash, crimson-hot icon, text-2 message.
struct ActionErrorStrip: View {
    let message: String
    var onRetry: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(AerieColor.crimsonHot)
                .padding(.top, 1)
            Text(message)
                .aerieFont(AerieFont.custom(.sans, size: 12))
                .foregroundStyle(AerieColor.text2)
                .lineSpacing(2)
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
        .background(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).fill(AerieColor.crimsonSoft))
        .overlay(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).strokeBorder(AerieColor.crimsonLine, lineWidth: 1))
        .padding(.bottom, 9)
    }
}

/// `.wt-err-dismiss` — a quiet bordered control that clears an
/// `ActionErrorStrip`: 500 11px text-3, glass-line border, 2pt radius; on hover
/// glass-3 fill, text-1, glass-line-2 border.
struct DismissButton: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Dismiss")
                .aerieFont(AerieFont.custom(.sans, size: 11).weight(.medium))
                .foregroundStyle(hovering ? AerieColor.text1 : AerieColor.text3)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).fill(hovering ? AerieColor.glass3 : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous).strokeBorder(hovering ? AerieColor.glassLine2 : AerieColor.glassLine, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
