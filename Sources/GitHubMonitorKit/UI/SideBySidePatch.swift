import AppKit
import SwiftUI

/// A patch in two columns: the old file on the left, the new on the right.
///
/// Both columns are given the same explicit width rather than left to size
/// themselves. Two columns that each took the width of their own longest
/// line would put the divider somewhere different in every file, and the
/// rows either side of it would stop lining up -- which is the one thing
/// this layout exists to do.
///
/// That width is measured in characters, not by laying the text out: the
/// font is monospaced, so a line's width is its length times one advance.
/// It costs nothing and gives the same answer.
struct SideBySidePatch: View {
    let patch: String
    let language: CodeLanguage?
    /// The width the two columns have to share, from the column the patch
    /// is drawn in.
    let available: CGFloat
    var fontSize: Double = Settings.defaultDiffFontSize
    var showsLineNumbers: Bool = true
    /// Which rows to draw. Nil draws them all; a range draws one stretch,
    /// which is how the patch is cut around the review comments.
    var only: Range<Int>?

    private var rows: [Row] {
        DiffCache.shared.rows(of: patch).enumerated().compactMap { offset, row in
            guard only.map({ $0.contains(offset) }) ?? true else { return nil }
            return Row(id: offset, row: row)
        }
    }

    /// As wide as the widest number in the file, so the code keeps one left
    /// edge down the column.
    private var gutterDigits: Int {
        guard showsLineNumbers else { return 0 }
        // From the rows, which are already worked out and kept: reading the
        // patch again here was a second pass over every line per frame.
        return max(String(DiffCache.shared.rows(of: patch).reduce(0) { widest, row in
            guard case .pair(let left, let right) = row else { return widest }
            return max(widest, left?.number ?? 0, right?.number ?? 0)
        }).count, 1)
    }

    private var font: Font { .system(size: fontSize).monospaced() }

    /// One character of the monospaced font the code is drawn in.
    private var advance: CGFloat {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).maximumAdvancement.width
    }

    /// What each column takes, text and gutter together.
    ///
    /// At least half of what is on offer, so a file of short lines fills
    /// the width instead of huddling at the left; wider where that side's
    /// own longest line asks for it, and then the whole thing scrolls
    /// sideways with both columns moving together, because they are the
    /// same code.
    private func widths(for measured: DiffWidths) -> (left: CGFloat, right: CGFloat) {
        let gutter = showsLineNumbers ? CGFloat(gutterDigits) * advance + Self.gutterPadding : 0
        let half = max((available - Self.dividerWidth) / 2, Self.narrowest)
        func column(_ characters: Int) -> CGFloat {
            max(half, gutter + CGFloat(characters) * advance + Self.textPadding)
        }

        var left = column(measured.left)
        var right = column(measured.right)
        // A hunk header is drawn across both columns, so the pair of them
        // has to be wide enough to hold it. Given to the right, which is
        // the side with room at its edge.
        let span = CGFloat(measured.span) * advance + Self.textPadding
        if left + Self.dividerWidth + right < span {
            right = span - left - Self.dividerWidth
        }
        return (left, right)
    }

    var body: some View {
        let all = rows
        // Measured over the whole file, not over the stretch being drawn:
        // columns sized per stretch would move the divider at every comment.
        let size = widths(for: DiffSideBySide.widths(of: DiffCache.shared.rows(of: patch)))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(all) { row in
                line(row.row, widths: size)
            }
        }
    }

    @ViewBuilder
    private func line(_ row: DiffSideRow, widths: (left: CGFloat, right: CGFloat)) -> some View {
        switch row {
        case .hunk(let text):
            // Across both columns: it is a line of neither file, and
            // repeating it on each side would read as two of them.
            span(text, kind: .hunk, widths: widths)
        case .note(let text):
            span(text, kind: .context, widths: widths)
        case .pair(let left, let right):
            HStack(spacing: 0) {
                cell(left, width: widths.left)
                Divider().frame(width: Self.dividerWidth)
                cell(right, width: widths.right)
            }
        }
    }

    private func span(
        _ text: String, kind: DiffLineKind, widths: (left: CGFloat, right: CGFloat)
    ) -> some View {
        CodeText(source: text, language: nil, font: font)
            .foregroundStyle(kind.textTint)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .frame(width: widths.left + Self.dividerWidth + widths.right, alignment: .leading)
            .background(kind.background, in: Rectangle())
    }

    /// One side of one row, or the blank that faces a line with nothing
    /// opposite it.
    ///
    /// The blank is tinted rather than left clear: an empty cell beside an
    /// added line is not "unchanged here", it is "this did not exist", and
    /// a clear gap reads as the former.
    @ViewBuilder
    private func cell(_ cell: DiffCell?, width: CGFloat) -> some View {
        if let cell {
            let kind = DiffLineKind(line: cell.text)
            HStack(spacing: 0) {
                if showsLineNumbers {
                    Text(verbatim: PatchLines.pad(cell.number, to: gutterDigits))
                        .font(font)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 12)
                }
                CodeText(
                    source: cell.text,
                    language: language,
                    font: font,
                    emphasis: cell.emphasis,
                    emphasisTint: kind.emphasis
                )
                    .foregroundStyle(kind.textTint)
                    .padding(.leading, showsLineNumbers ? 8 : 12)
                    .padding(.trailing, 12)
            }
            .padding(.vertical, 1)
            .frame(width: width, alignment: .leading)
            .background(kind.background, in: Rectangle())
        } else {
            Text(verbatim: " ")
                .font(font)
                .padding(.vertical, 1)
                .frame(width: width, alignment: .leading)
                .background(Self.absent, in: Rectangle())
        }
    }

    /// Nothing was here. Grey rather than clear, and fainter than either
    /// change colour, so it reads as absence and not as a third kind of
    /// change.
    private static let absent = Color(nsColor: .quaternaryLabelColor).opacity(0.18)

    private static let dividerWidth: CGFloat = 1
    private static let gutterPadding: CGFloat = 20
    private static let textPadding: CGFloat = 24
    /// Below this a column holds nothing worth reading, and the measurement
    /// is being taken before the layout has a width to give.
    private static let narrowest: CGFloat = 120

    private struct Row: Identifiable {
        let id: Int
        let row: DiffSideRow
    }
}
