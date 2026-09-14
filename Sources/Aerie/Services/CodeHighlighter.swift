import SwiftUI
import Splash

/// The language a diff line should be highlighted as, inferred from a filename.
enum CodeLanguage: Equatable {
    case swift
    /// Anything Splash can't tokenise — rendered as plain monospace.
    case other

    init(filename: String) {
        self = filename.lowercased().hasSuffix(".swift") ? .swift : .other
    }
}

/// Produces a foreground-colored `AttributedString` for a snippet of code.
/// Abstracted so the diff views don't depend on a concrete backend — a future
/// multi-language / context-aware highlighter (e.g. tree-sitter) can replace
/// `SplashCodeHighlighter` without touching the views.
protocol CodeHighlighter {
    func attributed(_ code: String, language: CodeLanguage) -> AttributedString
}

/// Swift-only highlighter backed by Splash. Non-Swift code degrades to a plain,
/// uncoloured `AttributedString` (still rendered with the diff's red/green wash
/// + monospace and the line's code tint, just without token colors).
final class SplashCodeHighlighter: CodeHighlighter {
    private let swift = Splash.SyntaxHighlighter(format: AttributedRunFormat())

    func attributed(_ code: String, language: CodeLanguage) -> AttributedString {
        switch language {
        case .swift:
            return swift.highlight(code)
        case .other:
            // No run colour: inherits the diff line's tint (text-2 / add / del).
            return AttributedString(code)
        }
    }
}

/// A Splash `OutputFormat` that assembles a SwiftUI `AttributedString` directly,
/// mapping Splash token types to the MARK III `.diff-line .tok-*` palette.
/// Plain text and untinted tokens carry no run colour, so they inherit the
/// diff line's own code colour (`.diff-line .code`, `.add`, `.del`). Building
/// the `AttributedString` ourselves (rather than via Splash's
/// `AttributedStringOutputFormat` → `NSAttributedString`) keeps full control of
/// the per-run colors and avoids font/color bridging.
struct AttributedRunFormat: OutputFormat {
    func makeBuilder() -> Builder { Builder() }

    struct Builder: OutputBuilder {
        private var result = AttributedString()

        init() {}

        mutating func addToken(_ token: String, ofType type: TokenType) {
            append(token, color: AttributedRunFormat.color(for: type),
                   italic: type == .comment)
        }

        mutating func addPlainText(_ text: String) {
            append(text, color: nil)
        }

        mutating func addWhitespace(_ whitespace: String) {
            result += AttributedString(whitespace)
        }

        func build() -> AttributedString { result }

        private mutating func append(_ text: String, color: SwiftUI.Color?, italic: Bool = false) {
            var run = AttributedString(text)
            run.foregroundColor = color
            if italic {
                run.inlinePresentationIntent = .emphasized
            }
            result += run
        }
    }

    /// `nil` = no run colour (inherit the line's code tint). The design names
    /// five token classes — `.tok-key`, `.tok-str`, `.tok-num`, `.tok-com`,
    /// `.tok-type`; everything else reads as plain code.
    static func color(for type: TokenType) -> SwiftUI.Color? {
        switch type {
        case .keyword:       return AerieColor.tokKeyword   // violet
        case .string:        return AerieColor.tokString    // green
        case .number:        return AerieColor.arc          // arc cyan
        case .comment:       return AerieColor.text4        // + italic
        case .type:          return AerieColor.amber        // gold
        case .preprocessing: return AerieColor.tokKeyword
        case .call, .property, .dotAccess, .custom:
            return nil
        }
    }
}
