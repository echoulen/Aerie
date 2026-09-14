import SwiftUI
import AppKit

/// Modal that shows the JSON request + response for a single MCP activity
/// entry. Opened from either an `MCPToast` "View request" button or from the
/// MCP settings activity row. Uses `DialogShell` (neutral tone); the
/// secondary action copies the pretty-printed response to the clipboard.
///
/// Visual contract: `v2/system.jsx` `DialogMCPViewRequest` — `.hud-note`
/// section titles (request in arc, response in text-4) over `.console` blocks.
/// The design's status pills (tool kind, HTTP status · latency) and bearer
/// note are omitted: this modal only receives the two JSON strings.
struct ViewRequestModal: View {
    let requestJSON: String
    let responseJSON: String
    var onClose: () -> Void

    var body: some View {
        DialogShell(
            tone: .neutral,
            title: "MCP request",
            subtitle: nil,
            primaryTitle: "Close",
            onPrimary: onClose,
            secondaryTitle: "Copy response",
            onSecondary: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prettyResponse, forType: .string)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                section(title: "Request", color: AerieColor.arc, body: prettyRequest)
                section(title: "Response", color: AerieColor.text4, body: prettyResponse)
            }
        }
    }

    private var prettyRequest: String { prettify(requestJSON) }
    private var prettyResponse: String { prettify(responseJSON) }

    /// Best-effort pretty-print. If the input doesn't decode as JSON, we just
    /// surface the original string verbatim — better than failing the modal.
    private func prettify(_ s: String) -> String {
        guard
            let data = s.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let out = String(data: pretty, encoding: .utf8)
        else { return s }
        return out
    }

    private func section(title: String, color: Color, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DialogNote(text: title, color: color)
            // `.console`: mono 11 / line-height 1.75, text-3 on black/0.46.
            ScrollView {
                Text(body)
                    .aerieFont(AerieFont.code(11))
                    .lineSpacing(5)
                    .foregroundStyle(AerieColor.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .dialogInset(fill: Color.black.opacity(0.46))
        }
    }
}
