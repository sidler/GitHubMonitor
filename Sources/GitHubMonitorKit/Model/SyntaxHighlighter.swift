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
    case html
    case twig
    case python
    case java
    case csharp
    case cpp
    case go
    case rust
    case swift
    case kotlin
    case ruby
    case sql
    case shell

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
        case "xml", "svg", "xsd", "xsl", "plist", "storyboard": return .xml
        case "html", "htm", "vue", "svelte": return .html
        case "twig", "jinja", "jinja2", "j2", "liquid", "njk": return .twig
        case "py", "python", "pyi": return .python
        case "java": return .java
        case "cs", "csharp", "c#": return .csharp
        case "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "c++": return .cpp
        case "go", "golang": return .go
        case "rs", "rust": return .rust
        case "swift": return .swift
        case "kt", "kts", "kotlin": return .kotlin
        case "rb", "ruby", "rake", "gemfile": return .ruby
        case "sql", "psql", "mysql": return .sql
        case "sh", "bash", "zsh", "shell", "ksh", "fish": return .shell
        default: return CodeLanguage(rawValue: name)
        }
    }

    public static func forFile(_ path: String) -> CodeLanguage? {
        let name = (path as NSString).lastPathComponent
        // Named files that carry no extension worth the name.
        switch name.lowercased() {
        case ".gitlab-ci.yml", "docker-compose.yml": return .yaml
        // Not a Makefile or a Dockerfile: both have a syntax of their own,
        // and painting them as shell would paint the wrong words.
        case ".bashrc", ".zshrc", ".profile", ".bash_profile": return .shell
        case "gemfile", "rakefile": return .ruby
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
        case .javascript, .typescript, .java, .csharp, .cpp, .go, .rust, .swift, .kotlin:
            ["//"]
        case .yaml, .python, .ruby, .shell: ["#"]
        case .sql: ["--"]
        case .css, .json, .xml, .html, .twig: []
        }
    }

    /// Opening and closing of a comment that spans lines.
    private var builtBlockComment: (open: String, close: String)? {
        switch self {
        case .php, .javascript, .typescript, .css, .java, .csharp, .cpp,
             .go, .rust, .swift, .kotlin, .sql:
            ("/*", "*/")
        case .xml, .html: ("<!--", "-->")
        // Twig's own comment, which is the one a template is written in.
        case .twig: ("{#", "#}")
        case .json, .yaml, .python, .ruby, .shell: nil
        }
    }

    private var builtStringDelimiters: [Character] {
        switch self {
        case .json: ["\""]
        case .javascript, .typescript, .go, .kotlin, .ruby, .shell:
            ["\"", "'", "`"]
        case .java, .csharp, .cpp, .rust, .swift: ["\"", "'"]
        case .php, .css, .yaml, .xml, .html, .twig, .python, .sql: ["\"", "'"]
        }
    }

    /// What a variable is introduced by, where the language says so.
    ///
    /// Only where it is unambiguous. PHP and the shell mark every variable
    /// this way, which is why `$this` and `$row` can be picked out of a
    /// line without parsing it; most other languages do not mark them at
    /// all, and guessing would paint every other word.
    var variableSigil: Character? {
        switch self {
        case .php, .shell: "$"
        default: nil
        }
    }

    /// Whether a name followed by `=` is an attribute rather than an
    /// assignment. True only where the two cannot be confused.
    var namesAttributes: Bool {
        switch self {
        case .xml, .html, .twig: true
        default: false
        }
    }

    /// Whether the language is written in tags.
    var hasTags: Bool {
        switch self {
        case .xml, .html, .twig: true
        default: false
        }
    }

    /// Whether `@name` introduces an annotation, a decorator or an
    /// attribute -- a name worth seeing, rather than an operator.
    var hasAnnotations: Bool {
        switch self {
        case .java, .kotlin, .python, .typescript, .javascript, .csharp: true
        default: false
        }
    }

    /// Whether a quoted string followed by `:` is the name of a field.
    var quotesFieldNames: Bool {
        switch self {
        case .json, .javascript, .typescript: true
        default: false
        }
    }

    /// Whether a backslash escapes the next character inside a string. Not in
    /// YAML's single quotes or in XML, where a backslash is just a backslash.
    var escapesInStrings: Bool {
        switch self {
        case .xml, .html, .twig, .yaml, .sql: false
        case .php, .javascript, .typescript, .css, .json, .python, .java,
             .csharp, .cpp, .go, .rust, .swift, .kotlin, .ruby, .shell:
            true
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
        case .python:
            [
                "and", "as", "assert", "async", "await", "break", "case", "class", "continue",
                "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if",
                "import", "in", "is", "lambda", "match", "nonlocal", "not", "or", "pass", "raise",
                "return", "try", "while", "with", "yield",
            ]
        case .java:
            [
                "abstract", "assert", "break", "case", "catch", "class", "const", "continue",
                "default", "do", "else", "enum", "extends", "final", "finally", "for", "goto",
                "if", "implements", "import", "instanceof", "interface", "native", "new",
                "package", "permits", "private", "protected", "public", "record", "return",
                "sealed", "static", "strictfp", "super", "switch", "synchronized", "this",
                "throw", "throws", "transient", "try", "var", "volatile", "while", "yield",
            ]
        case .csharp:
            [
                "abstract", "as", "async", "await", "base", "break", "case", "catch", "checked",
                "class", "const", "continue", "default", "delegate", "do", "else", "enum",
                "event", "explicit", "extern", "finally", "fixed", "for", "foreach", "goto",
                "if", "implicit", "in", "init", "interface", "internal", "is", "lock",
                "namespace", "new", "operator", "out", "override", "params", "private",
                "protected", "public", "readonly", "record", "ref", "return", "sealed",
                "sizeof", "stackalloc", "static", "switch", "this", "throw", "try", "typeof",
                "unchecked", "unsafe", "using", "var", "virtual", "volatile", "when", "where",
                "while", "with", "yield",
            ]
        case .cpp:
            [
                "alignas", "alignof", "asm", "auto", "break", "case", "catch", "class",
                "concept", "const", "const_cast", "consteval", "constexpr", "constinit",
                "continue", "decltype", "default", "define", "delete", "do", "dynamic_cast",
                "elif", "else", "endif", "enum", "explicit", "export", "extern", "for",
                "friend", "goto", "if", "ifdef", "ifndef", "include", "inline", "mutable",
                "namespace", "new", "noexcept", "operator", "pragma", "private", "protected",
                "public", "register", "reinterpret_cast", "requires", "return", "sizeof",
                "static", "static_assert", "static_cast", "struct", "switch", "template",
                "this", "thread_local", "throw", "try", "typedef", "typeid", "typename",
                "undef", "union", "using", "virtual", "volatile", "while",
            ]
        case .go:
            [
                "break", "case", "chan", "const", "continue", "default", "defer", "else",
                "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
                "map", "package", "range", "return", "select", "struct", "switch", "type",
                "var",
            ]
        case .rust:
            [
                "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
                "enum", "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match",
                "mod", "move", "mut", "pub", "ref", "return", "static", "struct", "super",
                "trait", "type", "unsafe", "use", "where", "while",
            ]
        case .swift:
            [
                "actor", "any", "associatedtype", "async", "await", "break", "case", "catch",
                "class", "continue", "defer", "deinit", "do", "else", "enum", "extension",
                "fallthrough", "fileprivate", "final", "for", "func", "guard", "if",
                "import", "in", "indirect", "init", "inout", "internal", "is", "lazy", "let",
                "mutating", "nonisolated", "nonmutating", "open", "operator", "private",
                "protocol", "public", "repeat", "required", "rethrows", "return", "self",
                "some", "static", "struct", "subscript", "super", "switch", "throw",
                "throws", "try", "typealias", "unowned", "var", "weak", "where", "while",
            ]
        case .kotlin:
            [
                "as", "break", "by", "catch", "class", "companion", "const", "constructor",
                "continue", "crossinline", "data", "do", "else", "enum", "external", "final",
                "finally", "for", "fun", "get", "if", "import", "in", "infix", "init",
                "inline", "inner", "interface", "internal", "is", "lateinit", "noinline",
                "object", "open", "operator", "out", "override", "package", "private",
                "protected", "public", "reified", "return", "sealed", "set", "super",
                "suspend", "tailrec", "this", "throw", "try", "typealias", "val", "var",
                "vararg", "when", "where", "while",
            ]
        case .ruby:
            [
                "alias", "and", "attr_accessor", "attr_reader", "attr_writer", "begin",
                "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end",
                "ensure", "for", "if", "in", "module", "next", "not", "or", "redo",
                "require", "require_relative", "rescue", "retry", "return", "self", "super",
                "then", "undef", "unless", "until", "when", "while", "yield",
            ]
        case .sql:
            [
                "all", "alter", "and", "as", "asc", "begin", "between", "by", "case", "cast",
                "check", "commit", "constraint", "create", "cross", "default", "delete",
                "desc", "distinct", "drop", "else", "end", "exists", "foreign", "from",
                "full", "group", "having", "in", "index", "inner", "insert", "into", "is",
                "join", "key", "left", "like", "limit", "not", "null", "offset", "on", "or",
                "order", "outer", "primary", "references", "returning", "right", "rollback",
                "select", "set", "table", "then", "transaction", "union", "unique", "update",
                "using", "values", "view", "when", "where", "with",
            ]
        case .shell:
            [
                "break", "case", "continue", "declare", "do", "done", "elif", "else", "esac",
                "eval", "exec", "export", "fi", "for", "function", "if", "in", "local",
                "readonly", "return", "select", "set", "shift", "source", "then", "trap",
                "unset", "until", "while",
            ]
        // Twig's own words. The template's HTML keeps its tags; these are
        // what the template adds to it.
        case .twig:
            [
                "and", "apply", "as", "autoescape", "block", "do", "else", "elseif", "embed",
                "endapply", "endautoescape", "endblock", "endembed", "endfilter", "endfor",
                "endif", "endmacro", "endset", "endverbatim", "endwith", "extends", "filter",
                "flush", "for", "from", "if", "import", "in", "include", "is", "macro", "not",
                "only", "or", "set", "use", "verbatim", "with",
            ]
        // HTML carries its structure in its tags, which have a colour of
        // their own, and in its attributes, which are named rather than
        // reserved. There is no list of words to keep.
        case .html: []
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
        case .python:
            [
                "False", "None", "True", "bool", "bytes", "dict", "float", "frozenset",
                "int", "list", "object", "self", "set", "str", "tuple", "type",
            ]
        case .java:
            [
                "Boolean", "Double", "Exception", "Integer", "List", "Long", "Map", "Object",
                "Optional", "Set", "String", "boolean", "byte", "char", "double", "false",
                "float", "int", "long", "null", "short", "true", "void",
            ]
        case .csharp:
            [
                "Dictionary", "Exception", "IEnumerable", "List", "Task", "bool", "byte",
                "char", "decimal", "double", "dynamic", "false", "float", "int", "long",
                "nint", "null", "nuint", "object", "sbyte", "short", "string", "true",
                "uint", "ulong", "ushort", "void",
            ]
        case .cpp:
            [
                "NULL", "auto", "bool", "char", "char16_t", "char32_t", "char8_t", "double",
                "false", "float", "int", "long", "nullptr", "short", "signed", "size_t",
                "string", "true", "unsigned", "vector", "void", "wchar_t",
            ]
        case .go:
            [
                "any", "bool", "byte", "complex64", "complex128", "error", "false",
                "float32", "float64", "int", "int8", "int16", "int32", "int64", "iota",
                "nil", "rune", "string", "true", "uint", "uint8", "uint16", "uint32",
                "uint64", "uintptr",
            ]
        case .rust:
            [
                "Box", "Err", "None", "Ok", "Option", "Result", "Self", "Some", "String",
                "Vec", "bool", "char", "f32", "f64", "false", "i8", "i16", "i32", "i64",
                "i128", "isize", "self", "str", "true", "u8", "u16", "u32", "u64", "u128",
                "usize",
            ]
        case .swift:
            [
                "Any", "AnyObject", "Array", "Bool", "Character", "Dictionary", "Double",
                "Error", "Float", "Int", "Int8", "Int16", "Int32", "Int64", "Never",
                "Optional", "Self", "Set", "String", "UInt", "Void", "false", "nil", "true",
            ]
        case .kotlin:
            [
                "Any", "Array", "Boolean", "Byte", "Char", "Double", "Float", "Int", "List",
                "Long", "Map", "Nothing", "Number", "Set", "Short", "String", "Unit",
                "false", "null", "true",
            ]
        case .ruby:
            [
                "Array", "Float", "Hash", "Integer", "String", "Symbol", "false", "nil",
                "true",
            ]
        case .sql:
            [
                "bigint", "blob", "boolean", "char", "date", "decimal", "double", "int",
                "integer", "json", "jsonb", "numeric", "real", "serial", "smallint", "text",
                "time", "timestamp", "uuid", "varchar",
            ]
        case .shell: ["false", "true"]
        case .twig: ["false", "none", "null", "true"]
        case .css, .json, .yaml, .xml, .html: []
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
        /// A variable the language marks as one: PHP's and the shell's
        /// `$name`. The thing a reader follows through a diff by eye, and
        /// the one word in `$this->total($row)` that says where the value
        /// came from.
        case variable
        /// A name with a `(` after it -- a call, or the declaration of
        /// one. The other half of what a signature says, after its types.
        case function
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
                // `"total":` names a field; `"total"` is one. Drawn apart
                // so an object reads as names and values rather than as a
                // column of red.
                let names = language.quotesFieldNames
                    && rest.dropFirst(text.count).drop(while: { $0 == " " }).first == ":"
                emit(String(text), names ? .type : .string)
                index = source.index(index, offsetBy: text.count)
                continue
            }
            if language.hasTags, let tag = tagName(in: rest) {
                emit(String(tag), .tag)
                index = source.index(index, offsetBy: tag.count)
                continue
            }
            // `{{`, `}}`, `{%` and `%}`: what a template adds to the markup
            // it is written over, and the first thing to look for in one.
            if language == .twig, let fence = twigFence(in: rest) {
                emit(String(fence), .keyword)
                index = source.index(index, offsetBy: fence.count)
                continue
            }
            if let marked = variable(in: rest, language: language) {
                emit(String(marked), .variable)
                index = source.index(index, offsetBy: marked.count)
                continue
            }
            if language.hasAnnotations, let marked = annotation(in: rest) {
                emit(String(marked), .type)
                index = source.index(index, offsetBy: marked.count)
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
                let after = rest.dropFirst(word.count)
                if types.contains(String(word)) {
                    emit(String(word), .type)
                } else if keywords.contains(word.lowercased()) {
                    emit(String(word), .keyword)
                } else if language.namesAttributes, after.first == "=" {
                    // In markup a name before `=` is an attribute. Only in
                    // markup: elsewhere it is an assignment, and painting
                    // the left of every one of those says nothing.
                    emit(String(word), .type)
                } else if after.first == "(" {
                    emit(String(word), .function)
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
        // PHP's `#[` opens an attribute. Read as a comment it swallowed
        // the declaration under it and turned the whole line grey.
        guard !(language == .php && rest.hasPrefix("#[")) else { return nil }
        guard language.lineComments.contains(where: { rest.hasPrefix($0) }) else { return nil }
        // Up to the newline, not including it: the break belongs to the text
        // around the comment, not to the comment.
        return rest.prefix { $0 != "\n" }
    }

    /// A variable, where the language marks one.
    ///
    /// `${NAME}` as well as `$name`, because a shell script is written in
    /// both and a diff of one is mostly these.
    private static func variable(
        in rest: Substring, language: CodeLanguage
    ) -> Substring? {
        guard let sigil = language.variableSigil, rest.first == sigil else { return nil }
        let after = rest.dropFirst()

        if after.first == "{" {
            guard let close = after.firstIndex(of: "}") else { return nil }
            return rest[rest.startIndex...close]
        }

        let name = after.prefix { isNameCharacter($0) }
        // A lone `$` is punctuation -- the end of a regular expression, or
        // PHP's variable variables -- and colouring it says nothing.
        guard !name.isEmpty else { return nil }
        return rest.prefix(1 + name.count)
    }

    /// `@Override`, `@property`, `@Input`: a name, not an operator.
    private static func annotation(in rest: Substring) -> Substring? {
        guard rest.first == "@" else { return nil }
        let name = rest.dropFirst().prefix { isNameCharacter($0) }
        guard let first = name.first, first.isLetter || first == "_" else { return nil }
        return rest.prefix(1 + name.count)
    }

    /// The braces a template speaks through.
    private static func twigFence(in rest: Substring) -> Substring? {
        for fence in ["{{", "}}", "{%-", "-%}", "{%", "%}"] where rest.hasPrefix(fence) {
            return rest.prefix(fence.count)
        }
        return nil
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

    /// What may stand in a name: letters, digits and `_`.
    ///
    /// Narrower than a word elsewhere here, which counts `-` so that CSS's
    /// `font-size` is one word and `@media` is another. In PHP a `-` is
    /// the start of `->`, and a variable that counted it took the arrow
    /// with it -- `$this-` rather than `$this`.
    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
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
