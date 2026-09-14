import SwiftUI

/// Bottom-right toast notification shown when an MCP write tool completes.
///
/// Visual contract: `v2/mcp.jsx` activity toast — a 340pt, 2pt-radius glass
/// card (glass-line-2 border, crimson on failure): a 22pt status tile, a mono
/// `mcp · <title>` header, the target line, an outcome row, and a recessed
/// footer with a plain "View request" text button.
///
/// The "View request" footer is only rendered when the toast carries a
/// `requestJSON` payload — info toasts without one just show the body.
struct MCPToast: View {
    let item: ToastItem
    var onViewRequest: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var viewHover = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                statusTile
                VStack(alignment: .leading, spacing: 4) {
                    header
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .aerieFont(AerieFont.custom(.sans, size: 13))
                            .foregroundStyle(AerieColor.text1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    outcomeRow
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AerieColor.text3)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if item.requestJSON != nil {
                HStack {
                    Spacer()
                    Button("View request", action: onViewRequest)
                        .buttonStyle(.plain)
                        .aerieFont(AerieFont.custom(.sans, size: 11).weight(.medium))
                        .foregroundStyle(viewHover ? AerieColor.text1 : AerieColor.text3)
                        .onHover { viewHover = $0 }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.18))
                .overlay(alignment: .top) {
                    Rectangle().fill(AerieColor.glassLine).frame(height: 1)
                }
            }
        }
        .frame(width: 340)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                Color(red: 28/255, green: 26/255, blue: 32/255).opacity(0.86)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        // `0 12px 30px -8px rgba(0,0,0,0.6)`
        .shadow(color: .black.opacity(0.6), radius: 12, y: 12)
    }

    /// `<amber>mcp</amber> · title` in mono 12.
    private var header: some View {
        (Text("mcp").foregroundColor(AerieColor.amber)
            + Text(" · \(item.title)").foregroundColor(AerieColor.text1))
            .aerieFont(AerieFont.code(12))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// `by agent` + the outcome word (success / failed). Info toasts omit it.
    @ViewBuilder
    private var outcomeRow: some View {
        switch item.tone {
        case .success, .error:
            HStack(spacing: 8) {
                Text("by agent")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text3)
                Text(item.tone == .success ? "success" : "failed")
                    .aerieFont(AerieFont.custom(.sans, size: 11))
                    .foregroundStyle(item.tone == .success ? AerieColor.ok : AerieColor.err)
            }
        case .info:
            EmptyView()
        }
    }

    private var statusTile: some View {
        let style = tileStyle
        return RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
            .fill(style.fill)
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(style.border, lineWidth: 1)
            )
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: style.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(style.glyph)
            )
    }

    private var tileStyle: (symbol: String, fill: Color, border: Color, glyph: Color) {
        switch item.tone {
        case .success: return ("checkmark", AerieColor.ok.opacity(0.18), AerieColor.ok.opacity(0.32), AerieColor.ok)
        case .error:   return ("xmark", AerieColor.crimson.opacity(0.18), AerieColor.crimson.opacity(0.36), AerieColor.err)
        case .info:    return ("info", AerieColor.amberSoft, AerieColor.amberLine, AerieColor.amber)
        }
    }

    private var borderColor: Color {
        item.tone == .error ? AerieColor.crimson.opacity(0.40) : AerieColor.glassLine2
    }
}

/// Bottom-trailing overlay that renders the live `ToastManager` stack. Hit
/// testing is enabled only when at least one toast is visible so it doesn't
/// swallow clicks against the underlying content.
struct ToastsOverlay: View {
    @Bindable var manager: ToastManager
    var onViewRequest: (ToastItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(manager.items) { item in
                MCPToast(
                    item: item,
                    onViewRequest: { onViewRequest(item) },
                    onDismiss: { manager.dismiss(item.id) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .onHover { manager.setHovered(item.id, $0) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(!manager.items.isEmpty)
    }
}
