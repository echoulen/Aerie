import SwiftUI

/// Key/value list used inside Aerie's confirmation dialogs.
///
/// Visual contract: `v2/dialogs.jsx` `KVList` — a recessed dark console panel
/// with a fixed mono telemetry label column (uppercase, tracked) and hairline
/// separators between rows. Values can be plain strings (via ``init(pairs:)``)
/// or styled views (via ``init(rows:)``) so a dialog can colour a value (e.g. a
/// crimson "dirty" line) or render it mono (paths / SHAs).
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
                    Text(row.key.uppercased())
                        .aerieFont(AerieFont.code(10))
                        .tracking(1.2)
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
        .dialogInset()
    }
}

extension View {
    /// The recessed console panel used inside dialogs (KV lists, PR previews,
    /// code / JSON blocks, text fields): a dark wash in a near-square plate with
    /// a glass hairline. `fill` lets a caller lighten or darken the wash.
    func dialogInset(fill: Color = Color.black.opacity(0.24)) -> some View {
        let shape = RoundedRectangle(cornerRadius: AerieMetric.radiusCard, style: .continuous)
        return self
            .background(fill)
            .clipShape(shape)
            .overlay(shape.strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }
}
