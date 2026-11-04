import Foundation

/// What one of the formatting buttons above the box does.
public enum MarkdownAction: String, CaseIterable, Sendable, Identifiable {
    case bold, italic, strikethrough, code, link
    case quote, bullet, number, task

    public var id: String { rawValue }
}

/// The markdown a formatting button writes, worked out on the text rather
/// than in the view.
///
/// Apart so it can be tested: every one of these is a small rule about
/// where characters go and where the selection lands afterwards, and
/// those are exactly the rules that are wrong the first time and that
/// nobody notices until a remark goes out with a stray asterisk in it.
///
/// Counted in UTF-16 throughout, which is what an `NSTextView` selection
/// is counted in -- hence `NSString` rather than `String` indices.
public enum MarkdownEditing {
    /// A body with the markdown written into it, and what to select next.
    public struct Written: Hashable, Sendable {
        public let text: String
        public let selection: NSRange

        public init(text: String, selection: NSRange) {
            self.text = text
            self.selection = selection
        }
    }

    public static func applying(
        _ action: MarkdownAction, to text: String, selection: NSRange
    ) -> Written {
        let string = text as NSString
        let range = clamped(selection, to: string.length)

        switch action {
        case .bold: return wrapping("**", in: string, over: range)
        case .italic: return wrapping("_", in: string, over: range)
        case .strikethrough: return wrapping("~~", in: string, over: range)
        case .code: return coding(string, over: range)
        case .link: return linking(string, over: range)
        case .quote, .bullet, .number, .task:
            return prefixing(action, in: string, over: range)
        }
    }

    // MARK: - Around a selection

    /// Puts a marker on both ends, or takes one off.
    ///
    /// Taking off looks at two places, because people select the word two
    /// ways: `**word**` chosen whole, and `word` chosen from inside the
    /// asterisks that are already there. Both mean "undo this".
    private static func wrapping(
        _ marker: String, in string: NSString, over range: NSRange
    ) -> Written {
        let marked = (marker as NSString).length
        let chosen = string.substring(with: range)

        if range.length >= marked * 2,
            chosen.hasPrefix(marker), chosen.hasSuffix(marker) {
            let inner = (chosen as NSString)
                .substring(with: NSRange(location: marked, length: range.length - marked * 2))
            return Written(
                text: string.replacingCharacters(in: range, with: inner),
                selection: NSRange(location: range.location, length: (inner as NSString).length)
            )
        }

        let outer = NSRange(
            location: range.location - marked, length: range.length + marked * 2
        )
        if outer.location >= 0, outer.upperBound <= string.length,
            string.substring(with: NSRange(location: outer.location, length: marked)) == marker,
            string.substring(
                with: NSRange(location: range.upperBound, length: marked)
            ) == marker {
            return Written(
                text: string.replacingCharacters(in: outer, with: chosen),
                selection: NSRange(location: outer.location, length: range.length)
            )
        }

        return Written(
            text: string.replacingCharacters(in: range, with: marker + chosen + marker),
            selection: NSRange(location: range.location + marked, length: range.length)
        )
    }

    /// Code: a fenced block where the selection spans lines, backticks
    /// where it does not.
    ///
    /// The number of backticks is counted rather than assumed. One
    /// backtick cannot hold a snippet that has a backtick in it -- which
    /// is most of the times a remark quotes markdown -- and markdown's
    /// own answer is to use more of them than the content does.
    private static func coding(_ string: NSString, over range: NSRange) -> Written {
        let chosen = string.substring(with: range)

        if chosen.contains("\n") {
            if chosen.hasPrefix("```\n"), chosen.hasSuffix("\n```") {
                let inner = (chosen as NSString).substring(
                    with: NSRange(location: 4, length: range.length - 8)
                )
                return Written(
                    text: string.replacingCharacters(in: range, with: inner),
                    selection: NSRange(
                        location: range.location, length: (inner as NSString).length
                    )
                )
            }
            // A fence has to start a line of its own, or it is three
            // backticks in the middle of a sentence.
            let lead = range.location > 0
                && string.substring(with: NSRange(location: range.location - 1, length: 1)) != "\n"
                ? "\n" : ""
            let block = lead + "```\n" + chosen + "\n```"
            return Written(
                text: string.replacingCharacters(in: range, with: block),
                selection: NSRange(
                    location: range.location + (lead as NSString).length + 4,
                    length: range.length
                )
            )
        }

        if let run = enclosingBackticks(of: chosen) {
            let inner = (chosen as NSString).substring(
                with: NSRange(location: run, length: range.length - run * 2)
            )
            let bare = inner.hasPrefix(" ") && inner.hasSuffix(" ") && inner.count > 1
                ? String(inner.dropFirst().dropLast())
                : inner
            return Written(
                text: string.replacingCharacters(in: range, with: bare),
                selection: NSRange(location: range.location, length: (bare as NSString).length)
            )
        }

        let fence = String(repeating: "`", count: longestBacktickRun(in: chosen) + 1)
        let pad = chosen.hasPrefix("`") || chosen.hasSuffix("`") ? " " : ""
        return Written(
            text: string.replacingCharacters(
                in: range, with: fence + pad + chosen + pad + fence
            ),
            selection: NSRange(
                location: range.location + (fence as NSString).length + (pad as NSString).length,
                length: range.length
            )
        )
    }

    /// The length of the equal runs of backticks on both ends, where the
    /// whole of the selection is one inline snippet.
    private static func enclosingBackticks(of chosen: String) -> Int? {
        let run = chosen.prefix { $0 == "`" }.count
        guard run > 0, chosen.suffix(run).allSatisfy({ $0 == "`" }),
            (chosen as NSString).length > run * 2
        else { return nil }
        return run
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    /// A link, with the caret left wherever the writing is not finished.
    ///
    /// What is selected decides which half is already known: an address
    /// wants a label, anything else wants an address.
    private static func linking(_ string: NSString, over range: NSRange) -> Written {
        let chosen = string.substring(with: range)
        if looksLikeAddress(chosen) {
            return Written(
                text: string.replacingCharacters(in: range, with: "[](\(chosen))"),
                selection: NSRange(location: range.location + 1, length: 0)
            )
        }
        return Written(
            text: string.replacingCharacters(in: range, with: "[\(chosen)]()"),
            selection: NSRange(location: range.upperBound + 3, length: 0)
        )
    }

    private static func looksLikeAddress(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(" "), !text.contains("\n") else { return false }
        let lower = text.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("www.")
    }

    // MARK: - In front of lines

    /// Puts a mark in front of every line the selection touches, or takes
    /// it off every one of them.
    ///
    /// Off only when they all have it: with a half-marked block the
    /// button means "mark the rest", which is what pressing it a second
    /// time on a growing list is for.
    private static func prefixing(
        _ action: MarkdownAction, in string: NSString, over range: NSRange
    ) -> Written {
        let block = string.lineRange(for: range)
        let text = string.substring(with: block)
        let ends = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if ends { lines.removeLast() }
        if lines.isEmpty { lines = [""] }

        let written = lines.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ? lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            : lines
        let on = written.allSatisfy { carries(action, $0) != nil }

        var number = 0
        let rewritten = lines.map { line -> String in
            // A blank line in the middle of a list stays blank: a mark on
            // nothing is a bullet with no words after it.
            if line.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 { return line }
            if on, let length = carries(action, line) {
                return String(line.dropFirst(length))
            }
            number += 1
            // A line that is already marked keeps its place rather than
            // collecting a second mark -- and a numbered one is counted
            // again from the top, which is what renumbers a list that has
            // grown in the middle.
            let bare = carries(action, line).map { String(line.dropFirst($0)) } ?? line
            return mark(action, number: number) + bare
        }

        let replacement = rewritten.joined(separator: "\n") + (ends ? "\n" : "")
        let result = string.replacingCharacters(in: block, with: replacement)

        // An empty selection is somebody typing, not somebody formatting a
        // block: the caret stays on its own line, shifted by whatever the
        // mark in front of it did.
        if range.length == 0, let first = lines.first, let now = rewritten.first {
            let shift = (now as NSString).length - (first as NSString).length
            let caret = max(block.location, range.location + shift)
            return Written(text: result, selection: NSRange(location: caret, length: 0))
        }

        return Written(
            text: result,
            selection: NSRange(
                location: block.location,
                length: (replacement as NSString).length - (ends ? 1 : 0)
            )
        )
    }

    /// How many characters of this line are already the mark, if it is
    /// there at all.
    private static func carries(_ action: MarkdownAction, _ line: String) -> Int? {
        switch action {
        case .quote:
            if line.hasPrefix("> ") { return 2 }
            return line.hasPrefix(">") ? 1 : nil
        case .task:
            let marks = ["- [ ] ", "- [x] ", "- [X] "]
            return marks.first(where: line.hasPrefix).map { $0.count }
        case .bullet:
            // A task is a bullet with a box on it, and taking "- " off one
            // would leave the box behind.
            guard carries(.task, line) == nil else { return nil }
            return ["- ", "* ", "+ "].first(where: line.hasPrefix).map { _ in 2 }
        case .number:
            let digits = line.prefix { $0.isNumber }
            guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
            return digits.count + 2
        default:
            return nil
        }
    }

    private static func mark(_ action: MarkdownAction, number: Int) -> String {
        switch action {
        case .quote: return "> "
        case .bullet: return "- "
        case .task: return "- [ ] "
        case .number: return "\(number). "
        default: return ""
        }
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        return NSRange(location: location, length: max(0, min(range.length, length - location)))
    }
}
