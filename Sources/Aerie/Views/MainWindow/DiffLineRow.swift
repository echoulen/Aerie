import SwiftUI

/// A single rendered line of a unified diff: old/new line-number gutters, a
/// +/−/space marker, and the syntax-highlighted content with an add/remove wash.
/// MARK III `.diff-*` palette: green add, crimson delete, with a 2pt leading
/// accent bar on changed lines.
struct DiffLineRow: View {
    let line: DiffLine
    let language: CodeLanguage
    let highlighter: CodeHighlighter

    private static let gutterWidth: CGFloat = 38

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(line.oldLineNo)
            gutter(line.newLineNo)
            Text(marker)
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(markerColor)
                .frame(width: 16, alignment: .center)
            Text(highlighter.attributed(line.text, language: language))
                .aerieFont(AerieFont.code(12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
        }
        .padding(.vertical, 1.5)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if line.kind != .context {
                Rectangle().fill(markerColor.opacity(0.7)).frame(width: 2)
            }
        }
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .aerieFont(AerieFont.code(11))
            .foregroundStyle(AerieColor.text4)
            .frame(width: Self.gutterWidth, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var marker: String {
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context:  return " "
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .addition: return AerieColor.diffAddText
        case .deletion: return AerieColor.diffDelText
        case .context:  return AerieColor.text4
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
