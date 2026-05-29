import SwiftUI

/// Key/value list used inside Aerie's confirmation dialogs. Renders a glass-1
/// surface with a fixed-width label column and a code-mono value column so
/// long paths / SHAs / numbers stay aligned.
struct KVList: View {
    let pairs: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .firstTextBaseline) {
                    Text(pair.0)
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.text3)
                        .frame(width: 130, alignment: .leading)
                    Text(pair.1)
                        .aerieFont(AerieFont.code(12))
                        .foregroundStyle(AerieColor.text1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(AerieColor.glass1)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
    }
}
