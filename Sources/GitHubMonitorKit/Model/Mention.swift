import Foundation

/// Somebody who can be named with an `@` in this repository.
public struct MentionableUser: Identifiable, Hashable, Sendable {
    /// What goes into the text after the `@`.
    public let login: String
    /// Their real name, where they have given one. Shown beside the
    /// login because a list of logins alone is a list of strangers.
    public let name: String?
    public let avatarURL: URL?

    public var id: String { login }

    public init(login: String, name: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// A repository's mentionable users, and by what was typed when asked.
///
/// Keyed like `LabelRequest` and for the same reason: narrowing can be
/// GitHub's work rather than ours, and the unnarrowed answer is not an
/// answer to a narrowed question.
public struct MentionRequest: Hashable, Sendable {
    public let repository: String
    public let query: String

    public init(repository: String, query: String) {
        self.repository = repository
        self.query = query
    }
}

public enum MentionCatalogueState: Equatable, Sendable {
    case loading
    case loaded(MentionQuery.Catalogue)
    case failed(String)
}

/// Reading an `@` out of half-written prose, at the caret.
///
/// The caret is what makes this honest. It used to read the end of the
/// text and nothing else, because `TextEditor` publishes its text and
/// nothing else -- so a name being fixed in the middle of a paragraph
/// was invisible. The box is an `NSTextView` now and says where the
/// insertion point is, so the mention being typed is the one in front of
/// it, wherever that is.
public enum MentionTyping {
    /// Characters GitHub allows in a login. A name stops at the first
    /// thing that is not one of these, which is what makes "@mira," and
    /// "(@mira)" read as the login they contain.
    private static func isLoginCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-"
    }

    /// Where the `@` of the mention being typed is, or nil when none is.
    ///
    /// Walks back from the caret over login characters. The first thing
    /// that is not one decides it: an `@` means a mention, anything else
    /// means the word in front of the caret is not one.
    public static func start(in text: String, before caret: String.Index) -> String.Index? {
        var index = caret
        while index > text.startIndex {
            let before = text.index(before: index)
            let character = text[before]
            if character == "@" {
                // An `@` inside a word is an address, a decorator, or a
                // handle somebody has already finished writing -- not the
                // start of a mention. GitHub reads it the same way.
                if before > text.startIndex {
                    let prior = text[text.index(before: before)]
                    guard prior.isWhitespace || prior.isNewline else { return nil }
                }
                return before
            }
            guard isLoginCharacter(character) else { return nil }
            index = before
        }
        return nil
    }

    /// What is being typed after an `@`, or nil when nothing is.
    ///
    /// Empty string is a real answer, and a different one from nil: it
    /// means the `@` has just been typed and everybody is a candidate.
    public static func query(in text: String, before caret: String.Index) -> String? {
        guard let at = start(in: text, before: caret) else { return nil }
        return String(text[text.index(after: at)..<caret])
    }

    /// The same, at the end of the text. What the box asked before it
    /// could say where its caret was.
    public static func query(in text: String) -> String? {
        query(in: text, before: text.endIndex)
    }

    /// The text with the half-typed name replaced by a whole one, and
    /// where the caret goes afterwards.
    ///
    /// A space goes in behind the name: it is settled, and what follows
    /// is the rest of the sentence rather than more of the name.
    public static func completing(
        _ text: String, with login: String, before caret: String.Index
    ) -> (text: String, caret: Int) {
        guard let at = start(in: text, before: caret) else {
            return (text, text.utf16.count)
        }
        // A space behind the name, unless the sentence already has one
        // there. Completing in the middle of a line otherwise leaves two,
        // which is the sort of thing nobody sees until it is committed.
        let follows = text[caret...].first
        let written = "@\(login)" + ((follows?.isWhitespace ?? false) ? "" : " ")
        let head = String(text[..<at])
        return (
            head + written + String(text[caret...]),
            (head + written).utf16.count
        )
    }

    public static func completing(_ text: String, with login: String) -> String {
        completing(text, with: login, before: text.endIndex).text
    }

    /// The caret, as an `NSTextView` counts it, turned into an index this
    /// can walk. Out-of-range offsets answer with the end of the text
    /// rather than trapping: a selection and the string it belongs to
    /// arrive from different places and can disagree for a moment.
    public static func index(ofUTF16 offset: Int, in text: String) -> String.Index {
        guard offset >= 0, offset <= text.utf16.count else { return text.endIndex }
        return String.Index(utf16Offset: offset, in: text)
    }
}
