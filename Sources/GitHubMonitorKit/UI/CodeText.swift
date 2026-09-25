import SwiftUI

/// Source, painted.
///
/// One `Text` built from an `AttributedString` rather than a row of views per
/// token: a run of coloured `Text`s laid out in an `HStack` cannot wrap, and
/// the layout cost of a few hundred of them is real. This way the whole block
/// is a single piece of text that happens to carry colour.
struct CodeText: View {
    let source: String
    let language: CodeLanguage?
    var font: Font = .caption.monospaced()

    var body: some View {
        Text(attributed)
            .font(font)
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for token in SyntaxHighlighter.tokens(source, language: language) {
            var piece = AttributedString(token.text)
            piece.foregroundColor = token.kind.tint
            result += piece
        }
        return result
    }
}

extension CodeToken.Kind {
    /// System colours, so both themes are covered without a palette of our
    /// own. Comments are grey rather than the green an editor would use: in a
    /// pane this narrow the point is to let the eye skip them.
    var tint: Color {
        switch self {
        case .plain: Color(nsColor: .labelColor)
        case .comment: Color(nsColor: .secondaryLabelColor)
        case .string: .red
        case .number: .blue
        case .keyword: .purple
        case .tag: .purple
        }
    }
}
