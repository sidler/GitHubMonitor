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

/// Reading an `@` out of half-written prose.
///
/// There is no caret to ask about. `TextEditor` publishes its text and
/// nothing else on this toolchain -- no selection, no insertion point --
/// so the only mention this can know about is the one at the end of what
/// has been typed. That covers writing, which is what somebody is doing
/// when they want this; it does not cover going back to fix a name in the
/// middle of a paragraph, and nothing here pretends otherwise.
public enum MentionTyping {
    /// Characters GitHub allows in a login. A name stops at the first
    /// thing that is not one of these, which is what makes "@mira," and
    /// "(@mira)" read as the login they contain.
    private static func isLoginCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-"
    }

    /// What is being typed after an `@`, or nil when nothing is.
    ///
    /// Empty string is a real answer, and a different one from nil: it
    /// means the `@` has just been typed and everybody is a candidate.
    public static func query(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }

        // An `@` in the middle of a word is an address, a decorator or a
        // handle somebody has already written -- not the start of a
        // mention. GitHub reads it the same way.
        if at > text.startIndex {
            let before = text[text.index(before: at)]
            guard before.isWhitespace || before.isNewline else { return nil }
        }

        let typed = text[text.index(after: at)...]
        // Anything that is not a login character means the mention is
        // finished and somebody has moved on to the next word.
        guard typed.allSatisfy(isLoginCharacter) else { return nil }
        return String(typed)
    }

    /// The text with the half-typed name replaced by a whole one.
    ///
    /// A space goes in behind it: the name is settled, and what follows
    /// is the rest of the sentence rather than more of the name.
    public static func completing(_ text: String, with login: String) -> String {
        guard let at = text.lastIndex(of: "@"), query(in: text) != nil else {
            return text
        }
        return String(text[..<at]) + "@\(login) "
    }
}
