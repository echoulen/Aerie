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

/// Swift-only highlighter backed by Splash. Non-Swift code degrades to a plain
/// `AttributedString` in the default code color (still rendered with the diff's
/// red/green wash + monospace, just without token colors).
final class SplashCodeHighlighter: CodeHighlighter {
    private let swift = Splash.SyntaxHighlighter(format: AttributedRunFormat())

    func attributed(_ code: String, language: CodeLanguage) -> AttributedString {
        switch language {
        case .swift:
            return swift.highlight(code)
        case .other:
            var plain = AttributedString(code)
            plain.foregroundColor = AttributedRunFormat.plainColor
            return plain
        }
    }
}

/// A Splash `OutputFormat` that assembles a SwiftUI `AttributedString` directly,
/// mapping Splash token types to a dark-theme palette tuned for Aerie. Building
/// the `AttributedString` ourselves (rather than via Splash's
/// `AttributedStringOutputFormat` → `NSAttributedString`) keeps full control of
/// the per-run colors and avoids font/color bridging.
struct AttributedRunFormat: OutputFormat {
    func makeBuilder() -> Builder { Builder() }

    static let plainColor = AerieColor.text1

    struct Builder: OutputBuilder {
        private var result = AttributedString()

        init() {}

        mutating func addToken(_ token: String, ofType type: TokenType) {
            append(token, color: AttributedRunFormat.color(for: type))
        }

        mutating func addPlainText(_ text: String) {
            append(text, color: AttributedRunFormat.plainColor)
        }

        mutating func addWhitespace(_ whitespace: String) {
            result += AttributedString(whitespace)
        }

        func build() -> AttributedString { result }

        private mutating func append(_ text: String, color: SwiftUI.Color) {
            var run = AttributedString(text)
            run.foregroundColor = color
            result += run
        }
    }

    static func color(for type: TokenType) -> SwiftUI.Color {
        switch type {
        case .keyword:       return Self.keyword
        case .string:        return Self.string
        case .type:          return Self.type
        case .call:          return Self.call
        case .number:        return Self.number
        case .comment:       return AerieColor.text3
        case .property:      return AerieColor.text2
        case .dotAccess:     return AerieColor.text2
        case .preprocessing: return Self.call
        case .custom:        return plainColor
        }
    }

    // Syntax palette — on-brand with the amber accent, calm and muted.
    private static let keyword = AerieColor.amber
    private static let type    = SwiftUI.Color(red: 0.56, green: 0.78, blue: 0.98) // soft blue
    private static let call    = SwiftUI.Color(red: 0.74, green: 0.69, blue: 0.98) // soft violet
    private static let number  = AerieColor.warn
    private static let string  = AerieColor.ok
}
