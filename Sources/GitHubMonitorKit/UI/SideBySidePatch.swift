import AppKit
import SwiftUI

/// A patch in two columns: the old file on the left, the new on the right.
///
/// Nothing here scrolls sideways. A line too long for its column wraps,
/// which is what finally made this layout simple: there are no scroll
/// views inside a file, nothing to keep in step, and the two sides of a
/// row share one height because they are one row.
///
/// Before that the file was cut into a piece per hunk and a piece per
/// comment, each piece a pair of scroll views kept level by passing
/// positions around -- and a review of forty files became hundreds of
/// scroll views sending one another messages.
///
/// The divider sits at the middle, always, so every file opens looking
/// the same.
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
        let width = columnWidth
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row.kind {
                case .threads(let here):
                    // Prose belongs to the row, not to a column: it is as
                    // wide as the pair of them.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(here) { ReviewThreadView(thread: $0) }
                    }
                    .frame(width: width * 2 + Self.dividerWidth, alignment: .leading)
                default:
                    // Both sides in one row, so a line that wraps on one
                    // side takes the other down with it and the two columns
                    // cannot drift apart.
                    HStack(alignment: .top, spacing: 0) {
                        cell(row, side: .old, width: width)
                        Divider().frame(width: Self.dividerWidth)
                        cell(row, side: .new, width: width)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One side of one row: its number, its marker and its code.
    private func cell(_ row: Row, side: ReviewThread.Side, width: CGFloat) -> some View {
        let text = self.text(row, side: side)
        let kind = text.map { DiffLineKind(line: $0.whole) }
        return HStack(alignment: .top, spacing: 0) {
            if showsLineNumbers {
                Text(verbatim: PatchLines.pad(number(row, side: side), to: gutterDigits))
                    .font(font)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 12)
                    .frame(width: gutterWidth, alignment: .topLeading)
            }

            if let text {
                // The marker in a column of its own, so what wraps lines up
                // under the code rather than where a `+` would be.
                Text(verbatim: text.marker)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .frame(width: markerWidth, alignment: .leading)

                CodeText(
                    source: text.body,
                    language: row.isHunk ? nil : language,
                    font: font,
                    emphasis: text.emphasis,
                    emphasisTint: kind?.emphasis ?? .clear
                )
                    .foregroundStyle(kind?.textTint ?? Color(nsColor: .labelColor))
                    .padding(.trailing, 12)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 1)
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(kind?.background ?? Self.absent, in: Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text?.whole ?? ""))
    }

    // MARK: - What a row holds

    private struct Piece {
        let whole: String
        let marker: String
        let body: String
        let emphasis: [ChangedRange]
    }

    private func text(_ row: Row, side: ReviewThread.Side) -> Piece? {
        switch row.kind {
        case .hunk(let line):
            let halves = DiffSideBySide.halves(ofHunk: line)
            let whole = side == .old ? halves.old : halves.new
            return Piece(whole: whole, marker: "", body: whole, emphasis: [])
        case .note(let line):
            // Whichever file it is about, the note is short enough to say
            // on both sides and the row needs the same height either way.
            return Piece(whole: line, marker: "", body: line, emphasis: [])
        case .threads:
            return nil
        case .pair(let left, let right):
            guard let cell = side == .old ? left : right else { return nil }
            let split = DiffWords.split(cell.text, emphasis: cell.emphasis)
            return Piece(
                whole: cell.text, marker: split.marker,
                body: split.body, emphasis: split.emphasis
            )
        }
    }

    private func number(_ row: Row, side: ReviewThread.Side) -> Int? {
        guard case .pair(let left, let right) = row.kind else { return nil }
        return (side == .old ? left : right)?.number
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

    /// One character, plus the room either side of it.
    private var markerWidth: CGFloat { advance + 10 }

    private var font: Font { .system(size: fontSize).monospaced() }

    private var advance: CGFloat {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).maximumAdvancement.width
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

        var isHunk: Bool { if case .hunk = kind { true } else { false } }
    }
}
