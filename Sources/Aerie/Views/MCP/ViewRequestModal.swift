import SwiftUI
import AppKit

/// Modal that shows the JSON request + response for a single MCP activity
/// entry. Opened from either an `MCPToast` "View request" button or from the
/// MCP settings activity row. Uses `DialogShell` (neutral tone); the
/// secondary action copies the pretty-printed response to the clipboard.
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
            VStack(alignment: .leading, spacing: 10) {
                section(title: "Request", body: prettyRequest)
                section(title: "Response", body: prettyResponse)
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

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .aerieFont(AerieFont.eyebrow())
                .foregroundStyle(AerieColor.text3)
            ScrollView {
                Text(body)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .padding(10)
            .background(AerieColor.glass1)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )
        }
    }
}
