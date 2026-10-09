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
        Text(PaintedCode.shared.text(for: self))
            .font(font)
            .textSelection(.enabled)
            // Wrapped rather than scrolled sideways. A line too long for
            // the column is read by letting it run on, not by dragging the
            // whole file under it; and in two columns, where each side has
            // half a window, most lines are too long.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    fileprivate var attributed: AttributedString {
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
        // Teal, which is far enough from the purple of the keywords beside
        // it that a signature reads as words and types rather than as one
        // coloured run.
        case .type: .teal
        case .tag: .purple
        // Orange and indigo are what is left that reads in both themes
        // without colliding with the four above: a variable is not a
        // string, a number, a keyword or a type, and in PHP it is the word
        // the eye follows down the column.
        case .variable: .orange
        case .function: .indigo
        }
    }
}

/// Lines already painted.
///
/// Building the `AttributedString` means scanning the line character by
/// character and appending a piece per token, and SwiftUI runs `body`
/// again on every frame of a scroll -- measured at five and a half
/// milliseconds for a screenful of a large PHP diff, a third of a frame
/// spent re-deriving something that had not changed.
///
/// Two generations rather than a queue with a least-recently-used order:
/// keeping that order means finding the entry on every hit, and finding it
/// means comparing whole lines. Here a hit is one lookup. When the new
/// generation fills, it becomes the old one and a fresh one starts, so
/// nothing is held for more than two turns and nothing has to be swept.
@MainActor
final class PaintedCode {
    static let shared = PaintedCode()

    /// What the painting depends on, and nothing else: the same line in the
    /// same language with the same stretches marked is the same picture,
    /// whatever row it is drawn in. The font is applied outside.
    private struct Key: Hashable {
        let source: String
        let language: CodeLanguage?
        let emphasis: [ChangedRange]
        let tint: Color
    }

    /// Enough for several screenfuls either side of the one being read.
    private let limit = 2048
    private var fresh: [Key: AttributedString] = [:]
    private var stale: [Key: AttributedString] = [:]

    func text(for code: CodeText) -> AttributedString {
        let key = Key(
            source: code.source, language: code.language,
            emphasis: code.emphasis, tint: code.emphasisTint
        )
        if let known = fresh[key] { return known }
        if let known = stale[key] {
            fresh[key] = known
            return known
        }

        let painted = code.attributed
        if fresh.count >= limit {
            stale = fresh
            fresh = [:]
        }
        fresh[key] = painted
        return painted
    }

    /// For the tests, and for anything that wants the measurement cold.
    func forget() {
        fresh.removeAll()
        stale.removeAll()
    }

    var count: Int { fresh.count + stale.count }
}
