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
    /// Stretches of this line that are not in the line it replaced, or that
    /// replaced it. Drawn bold and on a stronger band.
    var emphasis: [ChangedRange] = []
    /// The band those stretches sit on, which is the row's own colour at
    /// greater strength. Clear leaves them bold and nothing more.
    var emphasisTint: Color = .clear

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
        return marked(result)
    }

    /// Applies the changed stretches over the syntax colours.
    ///
    /// Over rather than instead: the word that changed is still code, and
    /// losing its colour to say it changed trades one thing the reader
    /// needs for another. Weight and ground are free -- the highlighter
    /// sets neither.
    ///
    /// Offsets are in characters, which is what the comparison counts in;
    /// `AttributedString` indexes the same way, so the two agree even where
    /// a line holds characters that are several bytes long.
    private func marked(_ text: AttributedString) -> AttributedString {
        guard !emphasis.isEmpty else { return text }
        var result = text
        let count = result.characters.count

        for range in emphasis {
            let start = max(0, min(range.location, count))
            let end = max(start, min(range.end, count))
            guard start < end else { continue }

            let from = result.index(result.startIndex, offsetByCharacters: start)
            let to = result.index(result.startIndex, offsetByCharacters: end)
            result[from..<to].inlinePresentationIntent = .stronglyEmphasized
            if emphasisTint != .clear {
                result[from..<to].backgroundColor = emphasisTint
            }
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
