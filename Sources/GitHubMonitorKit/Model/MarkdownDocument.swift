import Foundation

/// One piece of a comment body.
///
/// Only the block structure is modelled here. What happens inside a line --
/// bold, code spans, links -- is left to `AttributedString`'s own Markdown
/// parser at render time, which handles it well and is not worth repeating.
public enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case quote(String)
    /// Verbatim, with its fence removed.
    case code(String)
    /// Rows keyed by the table's header, which is how a five-column table
    /// fits into a pane four inches wide.
    case table(header: [String], rows: [[String]])
    case rule
}

/// Splits a GitHub comment body into blocks.
///
/// GitHub's own flavour, not CommonMark: a single newline is a line break
/// rather than a soft wrap, so paragraphs keep the shape their author gave
/// them. HTML is not rendered -- comment bodies use it for `<details>`
/// wrappers, which carry no information the text inside does not.
public enum MarkdownDocument {
    public static func blocks(from text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var lines = clean(text).components(separatedBy: .newlines)[...]

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        while let line = lines.first {
            lines = lines.dropFirst()
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let fence = fenceLanguage(trimmed) {
                _ = fence
                flushParagraph()
                var body: [String] = []
                while let next = lines.first, !isFence(next.trimmingCharacters(in: .whitespaces)) {
                    body.append(next)
                    lines = lines.dropFirst()
                }
                // Drop the closing fence, if the author wrote one.
                if lines.first != nil { lines = lines.dropFirst() }
                blocks.append(.code(body.joined(separator: "\n")))
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                continue
            }

            if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if isTableRow(trimmed) {
                flushParagraph()
                var rows = [trimmed]
                while let next = lines.first, isTableRow(next.trimmingCharacters(in: .whitespaces)) {
                    rows.append(next.trimmingCharacters(in: .whitespaces))
                    lines = lines.dropFirst()
                }
                blocks.append(table(from: rows))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted = [strippedQuote(trimmed)]
                while let next = lines.first, next.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(strippedQuote(next.trimmingCharacters(in: .whitespaces)))
                    lines = lines.dropFirst()
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            if let item = bulletItem(trimmed) {
                flushParagraph()
                var items = [item]
                while let next = lines.first,
                      let more = bulletItem(next.trimmingCharacters(in: .whitespaces)) {
                    items.append(more)
                    lines = lines.dropFirst()
                }
                blocks.append(.bullets(items))
                continue
            }

            if let item = numberedItem(trimmed) {
                flushParagraph()
                var items = [item]
                while let next = lines.first,
                      let more = numberedItem(next.trimmingCharacters(in: .whitespaces)) {
                    items.append(more)
                    lines = lines.dropFirst()
                }
                blocks.append(.numbered(items))
                continue
            }

            paragraph.append(line)
        }

        flushParagraph()
        return blocks
    }

    // MARK: - Preparation

    /// Removes what would only render as noise.
    ///
    /// `<summary>` keeps its text as a heading: in a bot's release notes it
    /// is the only label the section below it has.
    static func clean(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: "<!--.*?-->",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "<summary>(.*?)</summary>",
            with: "#### $1",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        // Badges and shields carry no information in a text pane, and their
        // markup is longer than the line they sit in.
        result = result.replacingOccurrences(
            of: "!\\[[^\\]]*\\]\\([^)]*\\)",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "</?(details|p|div|span|em|strong|blockquote|ul|ol|li|table|thead|tbody|tr|td|th)[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return result
    }

    // MARK: - Line kinds

    static func heading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return .heading(
            level: hashes.count,
            text: rest.trimmingCharacters(in: .whitespaces)
        )
    }

    static func isFence(_ line: String) -> Bool { line.hasPrefix("```") || line.hasPrefix("~~~") }

    static func fenceLanguage(_ line: String) -> String? {
        guard isFence(line) else { return nil }
        return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    /// Three or more of the same marker, and nothing else.
    static func isRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        for marker in ["-", "_", "*"] where line.allSatisfy({ String($0) == marker }) {
            return true
        }
        return false
    }

    static func isTableRow(_ line: String) -> Bool { line.hasPrefix("|") }

    static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
        let text = rest.dropFirst()
        guard text.first == " " else { return nil }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func strippedQuote(_ line: String) -> String {
        var rest = line.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    // MARK: - Tables

    static func table(from rows: [String]) -> MarkdownBlock {
        let parsed = rows.map(cells(in:))
        guard let header = parsed.first else { return .table(header: [], rows: []) }

        // The second row of a Markdown table is the alignment rule, which is
        // punctuation rather than content.
        let body = parsed.dropFirst().filter { !isAlignmentRow($0) }
        return .table(header: header, rows: Array(body))
    }

    static func isAlignmentRow(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }

    static func cells(in row: String) -> [String] {
        var trimmed = row
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
