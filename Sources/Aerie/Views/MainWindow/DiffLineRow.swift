import SwiftUI

/// A single rendered line of a unified diff (`.diff-line`): a `46px 46px 1fr`
/// grid of old/new line-number gutters (10.5pt text-4, right-aligned, 12pt
/// trailing padding) and the code — the +/−/space marker followed by the
/// syntax-highlighted text in mono 11.5pt at 1.65 line-height. Additions get a
/// green wash with mint code, deletions a crimson wash with rose code; context
/// code is text-2. The highlighter leaves plain runs uncoloured so they inherit
/// that per-line tint, while token runs keep their own colours (as the
/// `.tok-*` spans do inside `.code`).
struct DiffLineRow: View {
    let line: DiffLine
    let language: CodeLanguage
    let highlighter: CodeHighlighter

    private static let gutterWidth: CGFloat = 46

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            gutter(line.oldLineNo)
            gutter(line.newLineNo)
            (Text(marker) + Text(highlighter.attributed(line.text, language: language)))
                .aerieFont(AerieFont.code(11.5))
                .foregroundStyle(codeColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 14)
        }
        // 11.5pt × 1.65 line-height ≈ 19pt rows.
        .padding(.vertical, 2.5)
        .background(rowBackground)
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .aerieFont(AerieFont.code(10.5))
            .foregroundStyle(AerieColor.text4)
            .padding(.trailing, 12)
            .frame(width: Self.gutterWidth, alignment: .trailing)
    }

    private var marker: String {
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context:  return " "
        }
    }

    private var codeColor: Color {
        switch line.kind {
        case .addition: return AerieColor.diffAddText
        case .deletion: return AerieColor.diffDelText
        case .context:  return AerieColor.text2
        }
    }

    private var rowBackground: Color {
        switch line.kind {
        case .addition: return AerieColor.diffAddBg
        case .deletion: return AerieColor.diffDelBg
        case .context:  return .clear
        }
    }
}
