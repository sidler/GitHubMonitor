import Foundation

/// One of the words Conventional Comments puts at the head of a remark,
/// or one of the decorations that qualifies it.
///
/// The colour is the badge's colour, not a decoration of this app: it is
/// what `img.shields.io` is asked to draw, so the chip in the editor and
/// the badge in the comment are the same colour by construction rather
/// than by somebody remembering to keep two lists in step.
public struct ConventionalLabel: Identifiable, Hashable, Sendable {
    public let name: String
    /// What it is for. The chip's tooltip, and the reason somebody picks
    /// one word over another.
    public let summary: String
    /// Six hex digits, without a leading "#".
    public let colour: String

    public var id: String { name }

    public init(name: String, summary: String, colour: String) {
        self.name = name
        self.summary = summary
        self.colour = colour
    }

    /// The colour as fractions of one, or nil for anything unreadable.
    public var components: (red: Double, green: Double, blue: Double)? {
        IssueLabel(name: name, color: colour).components
    }

    /// Whether dark text reads better on it than white.
    public var prefersDarkText: Bool {
        IssueLabel(name: name, color: colour).prefersDarkText
    }
}

/// The head of a remark, in the form <https://conventionalcomments.org>
/// proposes: `<label> [decorations]: <subject>`.
///
/// Written here as a badge rather than as those words, which is a choice
/// about who reads it. The words are what the standard specifies and what
/// greps; the badge is what the browser extension most people run writes,
/// so a remark from this app sits beside theirs looking the same. The two
/// are the same statement, and both are recognised when one is already
/// there -- picking a second label replaces the first rather than stacking
/// on it, whichever way the first was written.
///
/// The badge's address and its colours are the extension's, read from
/// `pullpo-io/conventional-comments-helper`, so the two produce the same
/// bytes for the same label. Note, typo, polish and quibble are in the
/// standard but not in that extension; their colours were picked here,
/// from the same palette.
public enum ConventionalComment {
    /// The nine the standard strongly suggests, in its order, then the
    /// three it offers to anybody who wants to be more expressive.
    public static let labels: [ConventionalLabel] = [
        .init(
            name: "praise", summary: "Highlight something positive.", colour: "28A745"
        ),
        .init(
            name: "nitpick", summary: "A trivial, preference-based request.",
            colour: "F59E0B"
        ),
        .init(
            name: "suggestion", summary: "Propose a specific improvement.",
            colour: "3B82F6"
        ),
        .init(
            name: "issue", summary: "Point out a problem with the subject.",
            colour: "EF4444"
        ),
        .init(
            name: "todo", summary: "A small, trivial, but necessary change.",
            colour: "E879F9"
        ),
        .init(
            name: "question", summary: "Ask for clarification.", colour: "8B5CF6"
        ),
        .init(
            name: "thought", summary: "An idea that came of reviewing. Non-blocking.",
            colour: "6B7280"
        ),
        .init(
            name: "chore", summary: "A simple task to do before this is accepted.",
            colour: "F97316"
        ),
        .init(
            name: "note", summary: "Something to take note of. Always non-blocking.",
            colour: "0EA5E9"
        ),
        .init(name: "typo", summary: "A todo whose subject is a misspelling.", colour: "EC4899"),
        .init(
            name: "polish", summary: "Nothing is wrong; it could be better.",
            colour: "06B6D4"
        ),
        .init(name: "quibble", summary: "A nitpick, without the lice.", colour: "FBBF24"),
    ]

    /// The three the standard lists. An organisation may have its own, and
    /// those can still be typed -- this is what the chips offer, not what
    /// the format allows.
    public static let decorations: [ConventionalLabel] = [
        .init(
            name: "non-blocking", summary: "Should not hold the review up.",
            colour: "9CA3AF"
        ),
        .init(
            name: "blocking", summary: "Should hold the review up until it is settled.",
            colour: "374151"
        ),
        .init(
            name: "if-minor", summary: "Only worth doing if it turns out to be small.",
            colour: "14B8A6"
        ),
    ]

    public static func label(named name: String) -> ConventionalLabel? {
        labels.first { $0.name == name }
    }

    public static func decoration(named name: String) -> ConventionalLabel? {
        decorations.first { $0.name == name }
    }

    // MARK: - Writing one

    /// The markdown for a badge: a picture from shields.io wrapped in a
    /// link to what the label means, which is what the reader of a remark
    /// wants when they have not met the convention before.
    ///
    /// The trailing space is deliberate and matches the extension: the
    /// subject follows on the same line.
    public static func badge(label: String, decoration: String? = nil) -> String {
        let labelColour = self.label(named: label)?.colour ?? "6B7280"
        let address: String
        if let decoration, let colour = self.decoration(named: decoration)?.colour {
            address = "https://img.shields.io/badge/\(shields(label))-"
                + "\(shields(decoration))-\(colour)?labelColor=\(labelColour)"
        } else if let decoration {
            address = "https://img.shields.io/badge/\(shields(label))-"
                + "\(shields(decoration))-\(labelColour)"
        } else {
            address = "https://img.shields.io/badge/\(shields(label))-\(labelColour)"
        }

        let alt = decoration.map { "\(label)(\($0))" } ?? label
        var link = "https://pullpo.io/cc?l=\(escaped(label))"
        if let decoration { link += "&d=\(escaped(decoration))" }
        return "[![\(alt)](\(address))](\(link)) "
    }

    /// A badge's own escaping, which is not a URL's: shields.io reads a
    /// single dash as the separator between the two halves, so a dash
    /// that is part of a word -- `non-blocking`, `if-minor` -- is written
    /// twice to mean itself.
    private static func shields(_ text: String) -> String {
        escaped(
            text
                .replacingOccurrences(of: "-", with: "--")
                .replacingOccurrences(of: "_", with: "__")
        )
    }

    private static func escaped(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .conventionalUnreserved) ?? text
    }

    // MARK: - Reading one back

    /// What is already at the head of a body, and how much of it there is.
    ///
    /// Both forms are recognised, because both are written: the badge this
    /// app and the extension produce, and the plain words the standard
    /// specifies, which plenty of people type by hand.
    public static func head(of text: String) -> Head? {
        for pattern in [badgePattern, plainPattern] {
            guard
                let expression = try? NSRegularExpression(
                    pattern: pattern, options: [.caseInsensitive]
                ),
                let match = expression.firstMatch(
                    in: text, range: NSRange(text.startIndex..., in: text)
                ),
                let label = Range(match.range(at: 1), in: text)
            else { continue }
            let decoration = Range(match.range(at: 2), in: text).map { String(text[$0]) }
            return Head(
                label: String(text[label]).lowercased(),
                decoration: decoration?.lowercased(),
                length: match.range.length
            )
        }
        return nil
    }

    /// A head that is already on a body.
    public struct Head: Hashable, Sendable {
        public let label: String
        public let decoration: String?
        /// How many UTF-16 units it takes up, counted from the start.
        public let length: Int
    }

    /// Puts a label on a body, taking off whatever was there.
    ///
    /// A nil label takes the head off and leaves the prose, which is what
    /// pressing the lit chip again does.
    public static func applying(
        label: String?, decoration: String? = nil, to text: String
    ) -> Rewrite {
        let old = head(of: text)
        let body = String(text.dropFirst(utf16: old?.length ?? 0))
        let head = label.map { badge(label: $0, decoration: decoration) } ?? ""
        return Rewrite(
            text: head + body,
            bodyStart: head.utf16.count,
            oldLength: old?.length ?? 0
        )
    }

    /// A body with its head rewritten, and enough to put the caret back
    /// where the writing was.
    public struct Rewrite: Hashable, Sendable {
        public let text: String
        /// Where the prose begins now, in UTF-16 units.
        public let bodyStart: Int
        /// How long the head that was replaced was, so a caret that was
        /// in the prose can be moved by the difference rather than being
        /// thrown back to the start.
        public let oldLength: Int

        /// Where a caret that was at `offset` belongs now.
        public func caret(from offset: Int) -> Int {
            guard offset > oldLength else { return bodyStart }
            return offset - oldLength + bodyStart
        }
    }

    private static let names = labels.map(\.name).joined(separator: "|")
    private static let marks = decorations.map(\.name).joined(separator: "|")

    /// `[![issue(blocking)](https://img.shields.io/…)](https://pullpo.io/cc?…)`
    private static var badgePattern: String {
        "^\\s*\\[!\\[(\(names))(?:\\((\(marks))\\))?\\]"
            + "\\(https?://img\\.shields\\.io/badge/[^)]*\\)\\]"
            + "\\(https?://pullpo\\.io/cc\\?[^)]*\\)\\s*"
    }

    /// `issue (blocking): `, which is what the standard itself writes.
    private static var plainPattern: String {
        "^\\s*(?:\\*\\*)?(\(names))\\s*(?:\\((\(marks))\\))?:(?:\\*\\*)?\\s*"
    }
}

extension CharacterSet {
    /// What `encodeURIComponent` leaves alone, so the address this builds
    /// is byte-for-byte the extension's.
    fileprivate static let conventionalUnreserved = CharacterSet(
        charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )
}

extension String {
    /// Drops a number of UTF-16 units from the front, which is the unit
    /// an `NSRegularExpression` match and an `NSTextView` caret both come
    /// in.
    fileprivate func dropFirst(utf16 count: Int) -> Substring {
        guard count > 0 else { return self[...] }
        guard let index = utf16.index(
            utf16.startIndex, offsetBy: count, limitedBy: utf16.endIndex
        ), let bounded = String.Index(index, within: self) else { return self[...] }
        return self[bounded...]
    }
}
