import SwiftUI

/// Renders a comment body as Markdown.
///
/// Comment bodies are written as Markdown and were shown as their source,
/// which for anything a bot wrote meant a wall of pipes and brackets. The
/// block structure is laid out here; what happens inside a line is left to
/// `AttributedString`, which parses emphasis, code spans and links.
struct MarkdownText: View {
    let source: String
    /// How many blocks to draw before stopping. Nil reads the whole body;
    /// the popover sets a few, because it is a glance at a message rather
    /// than a place to read one.
    var blockLimit: Int?
    /// What is said where the text was cut. The default is written for the
    /// menu bar panel, whose "more" really is in the window; a summary of
    /// somebody else's issue has its rest on GitHub instead.
    var overflowNote: LocalizedStringKey = "More in the window"

    private var blocks: [MarkdownBlock] { MarkdownDocument.blocks(from: source) }

    var body: some View {
        let blocks = self.blocks
        let shown = blockLimit.map { Array(blocks.prefix($0)) } ?? blocks

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
            if shown.count < blocks.count {
                Text(overflowNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(heading(level))
                .padding(.top, 2)

        case .paragraph(let text):
            Text(inline(text))
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bullets(let items):
            list(items.map { (marker: Marker(item: $0), text: $0.text) })

        case .numbered(let items):
            list(items.enumerated().map {
                (marker: Marker.number("\($0.offset + 1)."), text: $0.element)
            })

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                    .frame(width: 3)
                Text(inline(text))
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let text, let language):
            // Horizontally scrollable: wrapping code changes what it says.
            ScrollView(.horizontal, showsIndicators: false) {
                CodeText(source: text, language: language)
                    .padding(8)
            }
            .background(
                Color(nsColor: .quaternaryLabelColor).opacity(0.4),
                in: RoundedRectangle(cornerRadius: 6)
            )

        case .table(let header, let rows):
            table(header: header, rows: rows)

        case .rule:
            Divider()
        }
    }

    /// What stands in front of a list item: a bullet, a number, or the box
    /// of a checklist.
    enum Marker: Hashable {
        case bullet
        case number(String)
        case task(done: Bool)

        init(item: BulletItem) {
            switch item.mark {
            case .bullet: self = .bullet
            case .task(let done): self = .task(done: done)
            }
        }
    }

    /// A dot and a box are not the same width, so both are drawn in a
    /// column of one width: without it a list that mixes them steps its
    /// text in and out again. Numbers keep their own width, because "10."
    /// does not fit in a dot's column.
    private static let bulletColumn: CGFloat = 13

    @ViewBuilder
    private func markerView(_ marker: Marker) -> some View {
        switch marker {
        case .bullet:
            Text(verbatim: "\u{2022}")
                .font(.callout)
                .frame(width: Self.bulletColumn, alignment: .center)
        case .number(let value):
            Text(verbatim: value)
                .font(.callout.monospacedDigit())
        // Left unpainted on purpose. The box already says which of the two
        // it is, and a colour here would claim that a checklist in someone
        // else's description is a status the app is reporting.
        case .task(let done):
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .font(.callout)
                .frame(width: Self.bulletColumn, alignment: .center)
        }
    }

    private func list(_ items: [(marker: Marker, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    markerView(item.marker)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text(inline(item.text))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// A table.
    ///
    /// Drawn as a grid while it has few enough columns for the pane it sits
    /// in, which is 280 to 400 points wide. Past that a grid gives every
    /// column four or five characters and the table says nothing, so the
    /// wide ones fall back to a group per row with each cell keyed by its
    /// heading -- no longer a table to look at, but still readable.
    @ViewBuilder
    private func table(header: [String], rows: [[String]]) -> some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        if columns <= Self.griddableColumns {
            grid(header: header, rows: rows, columns: columns)
        } else {
            keyedRows(header: header, rows: rows)
        }
    }

    /// How many columns the detail pane can still show side by side.
    private static let griddableColumns = 3

    /// The cells carry no width of their own: a `Grid` then sizes each
    /// column to what is in it, which is what keeps a column of numbers
    /// narrow and gives the room to the column of prose beside it.
    private func grid(header: [String], rows: [[String]], columns: Int) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 5) {
            if header.contains(where: { !$0.isEmpty }) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(inline(cell(header, column)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
                separator(columns)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(inline(cell(row, column)))
                            .font(.caption)
                    }
                }
                if index < rows.count - 1 {
                    separator(columns)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A rule across the whole width. `gridCellUnsizedAxes` so a divider
    /// does not ask for a width and stretch the columns around it.
    private func separator(_ columns: Int) -> some View {
        Divider()
            .gridCellUnsizedAxes(.horizontal)
            .gridCellColumns(columns)
    }

    private func keyedRows(header: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        if !cell.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if index < header.count, !header[index].isEmpty {
                                    Text(header[index])
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                }
                                Text(inline(cell))
                                    .font(.caption)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    Color(nsColor: .quaternaryLabelColor).opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
        }
    }

    /// A row is only as long as its author made it; a short one leaves the
    /// columns past its end empty rather than losing the grid a cell.
    private func cell(_ row: [String], _ index: Int) -> String {
        index < row.count ? row[index] : ""
    }

    private func heading(_ level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.semibold)
        case 2: .headline
        case 3: .subheadline.weight(.semibold)
        default: .callout.weight(.semibold)
        }
    }

    /// Emphasis, code spans and links, left to Foundation's own parser.
    ///
    /// `inlineOnlyPreservingWhitespace` so the line breaks the author put in
    /// survive: GitHub renders them, and a checklist folded into one
    /// paragraph is no longer a checklist.
    private func inline(_ text: String) -> AttributedString {
        let parsed = (try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(text)
        return Self.tinted(parsed)
    }

    /// Puts a band behind code spans.
    ///
    /// Foundation marks them but SwiftUI draws them like any other word, so
    /// `use the id, not the login` reads as a sentence with two odd nouns
    /// in it rather than as a sentence naming two fields. It matters most
    /// in review comments, which are mostly about named things.
    ///
    /// A band rather than a monospaced font: the font attribute would also
    /// fix the size, overriding whatever the view around it asked for, and
    /// a code span at the wrong size is worse than one at the right size
    /// without the shape.
    static func tinted(_ text: AttributedString) -> AttributedString {
        var result = text
        let spans = result.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            return run.range
        }
        for span in spans {
            result[span].backgroundColor = .secondary.opacity(0.22)
        }
        return result
    }
}
