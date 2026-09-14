import SwiftUI

/// Key/value list used inside Aerie's confirmation dialogs.
///
/// Visual contract: `v2/dialogs.jsx` `KVList` — a recessed dark panel (2pt
/// radius, glass-line border, black/0.22) with a fixed 130pt mono key column
/// (11pt text-4, lowercase, 0.02em tracking) and hairline separators between
/// rows. Values can be plain strings (via ``init(pairs:)``) or styled views
/// (via ``init(rows:)``) so a dialog can colour a value (e.g. a crimson "dirty"
/// line) or render it mono (paths / SHAs).
struct KVList: View {
    struct Row: Identifiable {
        let id = UUID()
        let key: String
        let value: AnyView

        init(_ key: String, _ value: AnyView) {
            self.key = key
            self.value = value
        }
    }

    let rows: [Row]

    /// Plain string values, rendered 13pt `text-1`.
    init(pairs: [(String, String)]) {
        self.rows = pairs.map { key, value in
            Row(key, AnyView(
                Text(value)
                    .aerieFont(AerieFont.custom(.sans, size: 13))
                    .foregroundStyle(AerieColor.text1)
            ))
        }
    }

    /// Styled values supplied by the caller.
    init(rows: [Row]) {
        self.rows = rows
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(row.key)
                        .aerieFont(AerieFont.code(11))
                        .tracking(0.22)
                        .foregroundStyle(AerieColor.text4)
                        .frame(width: 130, alignment: .leading)
                    row.value
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(AerieColor.glassLine)
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .dialogInset(fill: Color.black.opacity(0.22))
    }
}

extension View {
    /// The recessed panel used inside dialogs (KV lists, PR previews, text
    /// fields): a dark wash in a 2pt-radius box with a hairline border.
    func dialogInset(
        fill: Color = Color.black.opacity(0.22),
        border: Color = AerieColor.glassLine
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
        return self
            .background(fill)
            .clipShape(shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
    }
}
