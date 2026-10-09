import Foundation

/// The languages the highlighter knows, and how a file or a fence names them.
///
/// The set the work here is actually written in. Anything else is drawn
/// plainly, which is the honest outcome: a highlighter that guesses at a
/// language it does not know paints the wrong words.
public enum CodeLanguage: String, Hashable, Sendable, CaseIterable {
    case php
    case javascript
    case typescript
    case css
    case json
    case yaml
    case xml

    /// From the word after a Markdown fence, or from a file's extension.
    public static func named(_ raw: String?) -> CodeLanguage? {
        guard var name = raw?.lowercased() else { return nil }
        // A fence can carry more than a language: ```php title=foo
        name = String(name.prefix { !$0.isWhitespace })
        guard !name.isEmpty else { return nil }

        switch name {
        case "php", "php8", "phtml": return .php
        case "js", "javascript", "jsx", "mjs", "cjs", "node": return .javascript
        case "ts", "typescript", "tsx": return .typescript
        case "css", "scss", "sass", "less": return .css
        case "json", "jsonc", "json5": return .json
        case "yaml", "yml": return .yaml
        case "xml", "html", "htm", "svg", "xsd", "xsl", "twig": return .xml
        default: return CodeLanguage(rawValue: name)
        }
    }

    public static func forFile(_ path: String) -> CodeLanguage? {
        let name = (path as NSString).lastPathComponent
        // Named files that carry no extension worth the name.
        switch name.lowercased() {
        case ".gitlab-ci.yml", "docker-compose.yml": return .yaml
        default: break
        }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : named(ext)
    }

    // MARK: - What each language is made of
    //
    // Worked out once per language and kept, rather than rebuilt on every
    // read. These were computed properties returning a literal, and the
    // scan asks for the types and the keywords once per word and for the
    // comment and string markers once per character -- on a diff that
    // SwiftUI rebuilds at frame rate, tens of thousands of allocations a
    // second to answer a question whose answer never changes.

    var lineComments: [String] { Self.lineCommentTable[self] ?? [] }
    var blockComment: (open: String, close: String)? { Self.blockCommentTable[self] ?? nil }
    var stringDelimiters: [Character] { Self.stringDelimiterTable[self] ?? [] }
    var keywords: Set<String> { Self.keywordTable[self] ?? [] }
    var types: Set<String> { Self.typeTable[self] ?? [] }

    private static let lineCommentTable: [CodeLanguage: [String]] = table { $0.builtLineComments }
    private static let blockCommentTable: [CodeLanguage: (open: String, close: String)?] =
        table { $0.builtBlockComment }
    private static let stringDelimiterTable: [CodeLanguage: [Character]] =
        table { $0.builtStringDelimiters }
    private static let keywordTable: [CodeLanguage: Set<String>] = table { $0.builtKeywords }
    private static let typeTable: [CodeLanguage: Set<String>] = table { $0.builtTypes }

    private static func table<Value>(
        _ of: (CodeLanguage) -> Value
    ) -> [CodeLanguage: Value] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, of($0)) })
    }

    /// What starts a comment that runs to the end of the line.
    private var builtLineComments: [String] {
        switch self {
        case .php: ["//", "#"]
        case .javascript, .typescript: ["//"]
        case .yaml: ["#"]
        case .css, .json, .xml: []
        }
    }

    /// Opening and closing of a comment that spans lines.
    private var builtBlockComment: (open: String, close: String)? {
        switch self {
        case .php, .javascript, .typescript, .css: ("/*", "*/")
        case .xml: ("<!--", "-->")
        case .json, .yaml: nil
        }
    }

    private var builtStringDelimiters: [Character] {
        switch self {
        case .json: ["\""]
        case .javascript, .typescript: ["\"", "'", "`"]
        case .php, .css, .yaml, .xml: ["\"", "'"]
        }
    }

    /// Whether a backslash escapes the next character inside a string. Not in
    /// YAML's single quotes or in XML, where a backslash is just a backslash.
    var escapesInStrings: Bool {
        switch self {
        case .xml, .yaml: false
        case .php, .javascript, .typescript, .css, .json: true
        }
    }

    private var builtKeywords: Set<String> {
        switch self {
        case .php:
            [
                "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class",
                "clone", "const", "continue", "declare", "default", "die", "do", "echo", "else",
                "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch",
                "endwhile", "enum", "eval", "exit", "extends", "final", "finally", "fn", "for",
                "foreach", "function", "global", "goto", "if", "implements", "include",
                "include_once", "instanceof", "insteadof", "interface", "isset", "list", "match",
                "namespace", "new", "or", "print", "private", "protected", "public", "readonly",
                "require", "require_once", "return", "static", "switch", "throw", "trait", "try",
                "unset", "use", "var", "while", "xor", "yield",
                "true", "false", "null", "self", "parent", "this",
            ]
        case .javascript, .typescript:
            [
                "abstract", "as", "asserts", "async", "await", "break", "case", "catch", "class",
                "const", "continue", "debugger", "declare", "default", "delete", "do", "else",
                "enum", "export", "extends", "finally", "for", "from", "function", "get",
                "if", "implements", "import", "in", "infer", "instanceof", "interface", "is",
                "keyof", "let", "module", "namespace", "new", "of", "override", "private",
                "protected", "public", "readonly", "require", "return", "satisfies", "set",
                "static", "super", "switch", "this", "throw", "try", "type", "typeof", "var",
                "while", "with", "yield",
                "true", "false", "null", "undefined", "NaN", "Infinity",
            ]
        case .css:
            [
                "important", "media", "import", "keyframes", "supports", "charset", "font-face",
                "container", "layer", "property", "scope", "starting-style", "page", "namespace",
                "counter-style", "font-feature-values", "inherit", "initial", "unset", "revert",
                "auto", "none", "and", "not", "only", "from", "to",
            ]
        case .json: ["true", "false", "null"]
        case .yaml: ["true", "false", "null", "yes", "no", "on", "off", "~"]
        case .xml: []
        }
    }

    /// Names of types, told apart from the words that direct the flow.
    ///
    /// A signature is mostly types, and painting them the same purple as
    /// `public` and `function` leaves the one line a reader most wants to
    /// read as a wall of one colour. Matched as written rather than
    /// lowercased: PHP's are all lower case anyway, and `String` is not
    /// `string` anywhere else.
    private var builtTypes: Set<String> {
        switch self {
        case .php:
            [
                "array", "bool", "callable", "false", "float", "int", "iterable", "mixed",
                "never", "null", "object", "parent", "self", "static", "string", "true", "void",
            ]
        case .javascript, .typescript:
            [
                "any", "bigint", "boolean", "never", "number", "object", "string", "symbol",
                "undefined", "unknown", "void",
                "Array", "Date", "Error", "Map", "Promise", "Readonly", "Record", "RegExp", "Set",
                "WeakMap", "WeakSet",
            ]
        case .css, .json, .yaml, .xml: []
        }
    }
}

/// One run of source that is drawn in one colour.
public struct CodeToken: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case plain
        case comment
        case string
        case number
        case keyword
        /// A type's name. Its own colour because a signature is mostly
        /// types, and one colour over the whole of it says nothing.
        case type
        /// An XML or HTML tag name, which is what carries the structure
        /// there in place of keywords.
        case tag
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// Splits source into coloured runs.
///
/// A scanner rather than a parser, and deliberately so: this paints a diff in
/// a pane a few inches wide, where the difference between a correct parse and
/// a good guess is invisible. What it must not do is lose characters -- the
/// tokens always join back into exactly the source they came from, which is
/// the one property the tests pin down for every language.
public enum SyntaxHighlighter {
    public static func tokens(_ source: String, language: CodeLanguage?) -> [CodeToken] {
        guard let language, !source.isEmpty else {
            return source.isEmpty ? [] : [CodeToken(text: source, kind: .plain)]
        }

        // Read once for the whole line rather than once per word or per
        // character. Each is a dictionary lookup now instead of a rebuilt
        // literal, but a lookup per character is still a lookup per
        // character.
        let types = language.types
        let keywords = language.keywords

        var tokens: [CodeToken] = []
        var plain = ""
        var index = source.startIndex

        func flushPlain() {
            guard !plain.isEmpty else { return }
            tokens.append(CodeToken(text: plain, kind: .plain))
            plain = ""
        }
        func emit(_ text: String, _ kind: CodeToken.Kind) {
            flushPlain()
            tokens.append(CodeToken(text: text, kind: kind))
        }

        while index < source.endIndex {
            let rest = source[index...]

            if let comment = blockComment(in: rest, language: language) {
                emit(String(comment), .comment)
                index = source.index(index, offsetBy: comment.count)
                continue
            }
            if let comment = lineComment(in: rest, language: language) {
                emit(String(comment), .comment)
                index = source.index(index, offsetBy: comment.count)
                continue
            }
            if let text = string(in: rest, language: language) {
                emit(String(text), .string)
                index = source.index(index, offsetBy: text.count)
                continue
            }
            if language == .xml, let tag = tagName(in: rest) {
                emit(String(tag), .tag)
                index = source.index(index, offsetBy: tag.count)
                continue
            }

            let character = source[index]
            if character.isNumber, !isInsideWord(source, at: index) {
                let number = rest.prefix { $0.isNumber || $0 == "." || $0 == "_" }
                emit(String(number), .number)
                index = source.index(index, offsetBy: number.count)
                continue
            }
            if isWordStart(character) {
                let word = rest.prefix { isWordCharacter($0) }
                // A type first: PHP's `static` and `self` are both, and
                // in a signature -- which is where they nearly always are
                // in a diff -- the type is what the reader came for.
                if types.contains(String(word)) {
                    emit(String(word), .type)
                } else if keywords.contains(word.lowercased()) {
                    emit(String(word), .keyword)
                } else {
                    plain += word
                }
                index = source.index(index, offsetBy: word.count)
                continue
            }

            plain.append(character)
            index = source.index(after: index)
        }

        flushPlain()
        return tokens
    }

    // MARK: - Pieces

    private static func blockComment(
        in rest: Substring, language: CodeLanguage
    ) -> Substring? {
        guard let marker = language.blockComment, rest.hasPrefix(marker.open) else { return nil }
        let afterOpen = rest.index(rest.startIndex, offsetBy: marker.open.count)
        guard let close = rest[afterOpen...].range(of: marker.close) else {
            // Unterminated: a patch is a fragment, and half a comment is
            // still a comment.
            return rest
        }
        return rest[rest.startIndex..<close.upperBound]
    }

    private static func lineComment(
        in rest: Substring, language: CodeLanguage
    ) -> Substring? {
        guard language.lineComments.contains(where: { rest.hasPrefix($0) }) else { return nil }
        // Up to the newline, not including it: the break belongs to the text
        // around the comment, not to the comment.
        return rest.prefix { $0 != "\n" }
    }

    private static func string(in rest: Substring, language: CodeLanguage) -> Substring? {
        guard let quote = rest.first, language.stringDelimiters.contains(quote) else { return nil }

        var index = rest.index(after: rest.startIndex)
        while index < rest.endIndex {
            let character = rest[index]
            if character == "\\", language.escapesInStrings {
                index = rest.index(index, offsetBy: 2, limitedBy: rest.endIndex) ?? rest.endIndex
                continue
            }
            if character == quote {
                return rest[rest.startIndex...index]
            }
            // A quote that never closes on its line is punctuation -- an
            // apostrophe in a comment-free YAML value, say -- not a string
            // running to the end of the file.
            if character == "\n", quote != "`" { return nil }
            index = rest.index(after: index)
        }
        return rest
    }

    /// `<tag` or `</tag`, without the bracket, which stays plain.
    private static func tagName(in rest: Substring) -> Substring? {
        guard rest.hasPrefix("<") else { return nil }
        var index = rest.index(after: rest.startIndex)
        if index < rest.endIndex, rest[index] == "/" { index = rest.index(after: index) }
        let name = rest[index...].prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ":" }
        guard !name.isEmpty else { return nil }
        return rest[rest.startIndex..<name.endIndex]
    }

    private static func isWordStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$" || character == "@"
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
            || character == "-" || character == "@"
    }

    /// A digit inside an identifier is part of the identifier, not a number.
    private static func isInsideWord(_ source: String, at index: String.Index) -> Bool {
        guard index > source.startIndex else { return false }
        return isWordCharacter(source[source.index(before: index)])
    }
}
