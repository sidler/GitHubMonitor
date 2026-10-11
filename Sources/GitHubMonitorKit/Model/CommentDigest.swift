import Foundation

/// A remark in one line, for a list that has room for one.
///
/// A notification row used to say only what the thread was about. For a
/// mention that is the wrong half: the thing being reacted to is the
/// sentence somebody wrote, and it was two clicks away.
public enum CommentDigest {
    /// The first line worth reading, flattened.
    ///
    /// Markdown bodies open with all sorts of things that say nothing in a
    /// list: a template's HTML comment, a heading, a quote of what is being
    /// replied to, an image. Those are stepped over rather than shown, and
    /// what is left is squeezed onto one line -- a row is one line high
    /// however many the author used.
    public static func firstLine(of body: String, limit: Int = 160) -> String {
        var inComment = false

        for raw in body.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)

            if inComment {
                guard let end = line.range(of: "-->") else { continue }
                line = String(line[end.upperBound...]).trimmingCharacters(in: .whitespaces)
                inComment = false
            }
            while let start = line.range(of: "<!--") {
                let head = String(line[..<start.lowerBound])
                guard let end = line.range(of: "-->", range: start.upperBound..<line.endIndex)
                else {
                    inComment = true
                    line = head
                    break
                }
                line = (head + line[end.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            let stripped = strip(line)
            if !stripped.isEmpty { return shorten(stripped, to: limit) }
        }
        return ""
    }

    /// Takes the markers off the front of a line and the emphasis out of
    /// the middle, leaving the words.
    private static func strip(_ line: String) -> String {
        var text = Substring(line)

        // A quote is what somebody is answering, not what they said.
        guard !text.hasPrefix(">") else { return "" }
        // A rule, or the fence of a code block: neither reads as a line.
        guard !text.hasPrefix("---"), !text.hasPrefix("```"), !text.hasPrefix("|") else {
            return ""
        }

        while let first = text.first, "#*-+ \t".contains(first) {
            text = text.dropFirst()
        }
        // A list item's checkbox.
        if text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            text = text.dropFirst(4)
        }

        let flattened = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
        // An image or a bare link on its own line says nothing in a row.
        return flattened.hasPrefix("![") ? "" : flattened
    }

    private static func shorten(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        // On a word, so the line does not stop mid-syllable.
        guard let space = cut.lastIndex(of: " ") else { return cut + "\u{2026}" }
        return cut[..<space] + "\u{2026}"
    }
}
