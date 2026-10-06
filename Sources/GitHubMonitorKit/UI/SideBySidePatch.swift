import AppKit
import SwiftUI

/// A patch in two columns: the old file on the left, the new on the right.
///
/// One file is two scrolling columns and nothing else. It was briefly cut
/// into a piece per hunk and a piece per comment, each piece a pair of
/// scroll views kept level with the others by passing positions around --
/// and a review of forty files became hundreds of scroll views sending one
/// another messages, which is what made scrolling such a review wobble.
/// Nothing is kept in step here because there is nothing to keep in step:
/// each column of each file is one view holding every row of that column.
///
/// The divider sits at the middle, always. Sizing each side to its own
/// longest line put it somewhere different in every file, so a review was
/// read down a page whose shape changed at every heading. Each side then
/// scrolls sideways on its own, because at half a window most code does not
/// fit and the two sides rarely overflow by the same amount.
struct SideBySidePatch: View {
    let patch: String
    let language: CodeLanguage?
    /// The width the two columns share.
    let available: CGFloat
    var fontSize: Double = Settings.defaultDiffFontSize
    var showsLineNumbers: Bool = true
    /// The conversations to draw among the lines they hang on.
    var threads: [ReviewThread] = []

    var body: some View {
        let all = rows
        let width = columnWidth
        let gutter = gutterWidth
        let longest = DiffSideBySide.longest(in: DiffCache.shared.rows(of: patch))

        return HStack(spacing: 0) {
            column(
                all, side: .old, gutter: gutter, width: width,
                content: content(for: longest.left, in: width)
            )
            Divider().frame(width: Self.dividerWidth)
            column(
                all, side: .new, gutter: gutter, width: width,
                content: content(for: longest.right, in: width)
            )
        }
    }

    /// One whole column of one file: every row of that column, in one
    /// scrolling view.
    ///
    /// The numbers travel with their lines rather than sitting in a column
    /// of their own outside the scroll. Keeping them still means two
    /// stacks that have to agree on the height of every row, and a row of
    /// prose is as tall as its wrapping makes it -- so the still column
    /// either guesses or is handed a measurement, which is the kind of
    /// agreement between views this layout was rebuilt to be rid of.
    private func column(
        _ rows: [Row], side: ReviewThread.Side, gutter: CGFloat, width: CGFloat, content: CGFloat
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    line(row, side: side, gutter: gutter, width: content, column: width)
                }
            }
            .frame(width: content, alignment: .leading)
        }
        .frame(width: width)
    }

    /// One row of one column: its number and its text, or the prose that
    /// belongs between two lines.
    @ViewBuilder
    private func line(
        _ row: Row, side: ReviewThread.Side,
        gutter: CGFloat, width: CGFloat, column: CGFloat
    ) -> some View {
        if case .threads(let here) = row.kind {
            // Drawn on the left and held open on the right, at the column's
            // own width so both wrap the same and the two sides stay level.
            threadsView(here, width: column).opacity(side == .old ? 1 : 0)
        } else {
            HStack(spacing: 0) {
                if showsLineNumbers {
                    numbers(row, side: side, width: gutter)
                }
                cell(row, side: side, width: width - gutter)
            }
            .background(background(row, side: side), in: Rectangle())
        }
    }

    private func background(_ row: Row, side: ReviewThread.Side) -> Color {
        switch row.kind {
        case .hunk: DiffLineKind.hunk.background
        case .note, .threads: .clear
        case .pair(let left, let right):
            (side == .old ? left : right).map { DiffLineKind(line: $0.text).background }
                ?? Self.absent
        }
    }

    // MARK: - A row, on one side

    /// The number column's cell for one row.
    ///
    /// Carries its row's colour, so the band is not cut in two where the
    /// numbers stop and the code begins.
    @ViewBuilder
    private func numbers(_ row: Row, side: ReviewThread.Side, width: CGFloat) -> some View {
        switch row.kind {
        case .pair(let left, let right):
            Text(verbatim: PatchLines.pad((side == .old ? left : right)?.number, to: gutterDigits))
                .font(font)
                .foregroundStyle(.tertiary)
                .padding(.leading, 12)
                .padding(.vertical, 1)
                .frame(width: width, alignment: .leading)
        case .hunk, .note, .threads:
            // Neither file's line, so neither file numbers it.
            Text(verbatim: " ")
                .font(font)
                .padding(.vertical, 1)
                .frame(width: width, alignment: .leading)
        }
    }

    /// The code column's cell for one row.
    @ViewBuilder
    private func cell(_ row: Row, side: ReviewThread.Side, width: CGFloat) -> some View {
        switch row.kind {
        case .hunk(let text):
            let halves = DiffSideBySide.halves(ofHunk: text)
            code(side == .old ? halves.old : halves.new, width: width)
        case .note(let text):
            // Whichever file it is about, both sides need a row of the same
            // height, and the note is short enough to say twice.
            code(text, width: width)
        case .threads:
            EmptyView()
        case .pair(let left, let right):
            patch(side == .old ? left : right, width: width)
        }
    }

    private func code(_ text: String, width: CGFloat) -> some View {
        CodeText(source: text, language: nil, font: font)
            .foregroundStyle(DiffLineKind.hunk.textTint)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .frame(width: width, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
    }

    /// One side of one line, or the blank facing a line with nothing
    /// opposite it.
    ///
    /// The blank is tinted rather than left clear: an empty cell beside an
    /// added line is not "unchanged here", it is "this did not exist", and
    /// a clear gap reads as the former.
    @ViewBuilder
    private func patch(_ cell: DiffCell?, width: CGFloat) -> some View {
        if let cell {
            let kind = DiffLineKind(line: cell.text)
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
                .padding(.vertical, 1)
                .frame(width: width, alignment: .leading)
                // One element per line rather than one per coloured token.
                // Resolving the attributed text of every token is where
                // nearly all of the layout time went on a large diff.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: cell.text))
        } else {
            Text(verbatim: " ")
                .font(font)
                .padding(.vertical, 1)
                .frame(width: width, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    /// Prose is given the column's own width rather than the content's, so
    /// the copy held open on the other side wraps identically and the two
    /// columns stay level.
    private func threadsView(_ threads: [ReviewThread], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(threads) { ReviewThreadView(thread: $0) }
        }
        .frame(width: max(width, Self.narrowest), alignment: .leading)
    }

    // MARK: - Measuring

    /// Half of what is on offer, less half the divider.
    private var columnWidth: CGFloat {
        max((available - Self.dividerWidth) / 2, Self.narrowest)
    }

    /// As wide as the widest number in the file, so the code keeps one left
    /// edge down the column.
    private var gutterDigits: Int {
        guard showsLineNumbers else { return 0 }
        return max(String(DiffCache.shared.rows(of: patch).reduce(0) { widest, row in
            guard case .pair(let left, let right) = row else { return widest }
            return max(widest, left?.number ?? 0, right?.number ?? 0)
        }).count, 1)
    }

    private var gutterWidth: CGFloat {
        guard showsLineNumbers else { return 0 }
        return CGFloat(gutterDigits) * advance + Self.gutterPadding
    }

    private var font: Font { .system(size: fontSize).monospaced() }

    /// One character of the monospaced font the code is drawn in.
    private var advance: CGFloat {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).maximumAdvancement.width
    }

    /// How wide a row is drawn: the column, or the longest line in it where
    /// that is longer. Measured over the whole file, so the colour bands
    /// keep running across a row however far it is scrolled.
    private func content(for characters: Int, in column: CGFloat) -> CGFloat {
        max(column, CGFloat(characters) * advance + Self.textPadding)
    }

    // MARK: - Rows

    /// Every row of the file, in order, with the conversations among them.
    private var rows: [Row] {
        let patchRows = DiffCache.shared.rows(of: patch)
        let anchors = ReviewThreadAnchors.sideBySide(rows: patchRows, threads: threads)

        var result: [Row] = []
        for (index, row) in patchRows.enumerated() {
            switch row {
            case .hunk(let text): result.append(Row(id: result.count, kind: .hunk(text)))
            case .note(let text): result.append(Row(id: result.count, kind: .note(text)))
            case .pair(let left, let right):
                result.append(Row(id: result.count, kind: .pair(left, right)))
            }
            if let here = anchors[index] {
                result.append(Row(id: result.count, kind: .threads(here)))
            }
        }
        return result
    }

    private static let absent = Color(nsColor: .quaternaryLabelColor).opacity(0.18)
    private static let dividerWidth: CGFloat = 1
    private static let gutterPadding: CGFloat = 20
    private static let textPadding: CGFloat = 24
    /// Below this a column holds nothing worth reading, and the measurement
    /// is being taken before the layout has a width to give.
    private static let narrowest: CGFloat = 120

    private struct Row: Identifiable {
        enum Kind {
            case hunk(String)
            case note(String)
            case pair(DiffCell?, DiffCell?)
            case threads([ReviewThread])
        }

        let id: Int
        let kind: Kind
    }
}
