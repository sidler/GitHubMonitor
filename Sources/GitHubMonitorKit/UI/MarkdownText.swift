import SwiftUI

/// Renders a comment body as Markdown.
///
/// Comment bodies are written as Markdown and were shown as their source,
/// which for anything a bot wrote meant a wall of pipes and brackets. The
/// block structure is laid out here; what happens inside a line is left to
/// `AttributedString`, which parses emphasis, code spans and links.
struct MarkdownText: View {
    let source: String

    private var blocks: [MarkdownBlock] { MarkdownDocument.blocks(from: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
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
            list(items.map { (marker: "•", text: $0) })

        case .numbered(let items):
            list(items.enumerated().map { (marker: "\($0.offset + 1).", text: $0.element) })

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

        case .code(let text):
            // Horizontally scrollable: wrapping code changes what it says.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.caption.monospaced())
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

    private func list(_ items: [(marker: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.marker)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text(inline(item.text))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// A table as one labelled group per row.
    ///
    /// A pane this narrow cannot hold five columns side by side; keying each
    /// cell by its column heading keeps every value readable and its meaning
    /// attached to it.
    private func table(header: [String], rows: [[String]]) -> some View {
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
        (try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(text)
    }
}
