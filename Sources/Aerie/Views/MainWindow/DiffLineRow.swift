import SwiftUI

/// A single rendered line of a unified diff (`.diff-line`): a `46px 46px 1fr`
/// grid of old/new line-number gutters (10.5pt text-4, right-aligned, 12pt
/// trailing padding) and the code — the +/−/space marker followed by the
/// syntax-highlighted text in mono 11.5pt at 1.65 line-height. Additions get a
/// green wash with mint code, deletions a crimson wash with rose code; context
/// code is text-2. The highlighter leaves plain runs uncoloured so they inherit
/// that per-line tint, while token runs keep their own colours (as the
/// `.tok-*` spans do inside `.code`).
///
/// `singleGutter` is the compact layout (`CompactReview`): one 32pt gutter (the
/// new line number, or the old one for a deletion), 10.5pt wrapped code.
struct DiffLineRow: View {
    let line: DiffLine
    let language: CodeLanguage
    let highlighter: CodeHighlighter
    var singleGutter: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if singleGutter {
                gutter(line.newLineNo ?? line.oldLineNo)
            } else {
                gutter(line.oldLineNo)
                gutter(line.newLineNo)
            }
            (Text(marker) + Text(highlighter.attributed(line.text, language: language)))
                .aerieFont(AerieFont.code(singleGutter ? 10.5 : 11.5))
                .foregroundStyle(codeColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, singleGutter ? 12 : 14)
        }
        // 11.5pt × 1.65 ≈ 19pt rows; compact 10.5pt × 1.6 ≈ 17pt.
        .padding(.vertical, singleGutter ? 1.5 : 2.5)
        .background(rowBackground)
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .aerieFont(AerieFont.code(singleGutter ? 9.5 : 10.5))
            .foregroundStyle(AerieColor.text4)
            .padding(.trailing, singleGutter ? 9 : 12)
            .frame(width: singleGutter ? 32 : 46, alignment: .trailing)
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
