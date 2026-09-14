import SwiftUI

/// Bottom-right toast notification shown when an MCP write tool completes.
/// MARK III: a small chamfered deep-space plate with a tone-tinted hairline and
/// leading strut (ok green / crimson / gold).
///
/// The "View request" affordance is only rendered when the toast carries a
/// `requestJSON` payload — info toasts without one just show title/subtitle.
struct MCPToast: View {
    let item: ToastItem
    var onViewRequest: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            toneIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .aerieFont(AerieFont.body().weight(.medium))
                    .foregroundStyle(AerieColor.text1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.text3)
                }
                if item.requestJSON != nil {
                    Button("View request", action: onViewRequest)
                        .buttonStyle(.hud(.standard, size: .small))
                        .padding(.top, 4)
                }
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
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding([.trailing, .vertical], 14)
        .frame(width: 340)
        .background(toastSurface)
        .clipShape(HudPlateShape(cut: 12))
        .overlay(HudPlateShape(cut: 12).strokeBorder(toneStroke, lineWidth: 1))
        // Tone strut down the leading edge (`.card::after`, tinted to the tone).
        .overlay(alignment: .leading) {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: toneColor, location: 0.25),
                .init(color: toneColor, location: 0.75),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: 2)
            .padding(.vertical, 10)
            .shadow(color: toneColor.opacity(0.6), radius: 4)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    // Deep-space dialog glass: in-window blur under the near-black surface.
    private var toastSurface: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            AerieColor.dialogSurface
            LinearGradient(stops: [
                .init(color: AerieColor.cardSheen.opacity(0.05), location: 0),
                .init(color: .clear, location: 0.5),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    private var toneColor: Color { toneIconStyle.1 }

    private var toneIcon: some View {
        let (sym, color) = toneIconStyle
        return Image(systemName: sym)
            .font(.system(size: 16))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
    }

    private var toneIconStyle: (String, Color) {
        switch item.tone {
        case .success: return ("checkmark.circle.fill", AerieColor.ok)
        case .error:   return ("exclamationmark.octagon.fill", AerieColor.err)
        case .info:    return ("info.circle.fill", AerieColor.amber)
        }
    }

    private var toneStroke: Color {
        switch item.tone {
        case .success: return AerieColor.ok.opacity(0.4)
        case .error:   return AerieColor.crimsonLine
        case .info:    return AerieColor.amberLine
        }
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
