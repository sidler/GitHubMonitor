import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Syntax highlighting")
struct SyntaxHighlighterTests {
    private func kinds(_ source: String, _ language: CodeLanguage?) -> [CodeToken.Kind] {
        SyntaxHighlighter.tokens(source, language: language).map(\.kind)
    }

    private func text(_ source: String, _ language: CodeLanguage?, of kind: CodeToken.Kind) -> [String] {
        SyntaxHighlighter.tokens(source, language: language)
            .filter { $0.kind == kind }
            .map(\.text)
    }

    /// The one property worth guaranteeing: a scanner that loses a character
    /// has changed the code it was asked to display.
    @Test("The tokens always join back into the source", arguments: CodeLanguage.allCases)
    func lossless(language: CodeLanguage) {
        let samples = [
            "",
            "plain text",
            "<?php\n// a comment\n$x = 'quoted'; /* block */ return 42;\n",
            "const a = `back ${tick}`; // trailing\n",
            "{\"a\": 1, \"b\": [true, null]}\n",
            "key: 'value' # note\nlist:\n  - 1\n",
            "<root attr=\"v\"><!-- c --></root>\n",
            "/* unterminated",
            "it's an apostrophe, unpaired\n",
        ]
        for sample in samples {
            let rejoined = SyntaxHighlighter.tokens(sample, language: language).map(\.text).joined()
            #expect(rejoined == sample, "lost characters in \(language.rawValue): \(sample.debugDescription)")
        }
    }

    @Test("Without a language nothing is painted")
    func unknownLanguage() {
        #expect(kinds("class Foo {}", nil) == [.plain])
        #expect(SyntaxHighlighter.tokens("", language: .php).isEmpty)
    }

    @Test("PHP: keywords, strings, comments and numbers")
    func php() {
        let source = "public function run(): int { // start\n  $n = 42; return $n; }"
        #expect(text(source, .php, of: .keyword) == ["public", "function", "return"])
        // The newline is not part of the comment; it belongs to the flow.
        #expect(text(source, .php, of: .comment) == ["// start"])
        #expect(text(source, .php, of: .number) == ["42"])
    }

    /// A hash opens a comment in PHP too, and `#[Attribute]` is common in
    /// modern code -- so this is a place the scanner is knowingly rough.
    @Test("PHP: a hash comment runs to the end of the line")
    func phpHash() {
        #expect(text("# note\n$a = 1;", .php, of: .comment) == ["# note"])
    }

    @Test("JavaScript: template literals may span lines")
    func javascript() {
        let source = "const greeting = `hello\nworld`;\nlet n = 3.14;"
        #expect(text(source, .javascript, of: .string) == ["`hello\nworld`"])
        #expect(text(source, .javascript, of: .keyword) == ["const", "let"])
        #expect(text(source, .javascript, of: .number) == ["3.14"])
    }

    /// A digit inside a name is part of the name: `utf8` is not the number 8.
    @Test("A digit inside an identifier is not a number")
    func digitsInNames() {
        #expect(text("$charset = utf8mb4;", .php, of: .number).isEmpty)
        #expect(text("const x2 = 7;", .javascript, of: .number) == ["7"])
    }

    @Test("JSON: only double quotes, and the three literals")
    func json() {
        let source = "{\"name\": \"it's fine\", \"ok\": true, \"n\": 12}"
        #expect(text(source, .json, of: .string) == ["\"name\"", "\"it's fine\"", "\"ok\"", "\"n\""])
        #expect(text(source, .json, of: .keyword) == ["true"])
        #expect(text(source, .json, of: .number) == ["12"])
    }

    @Test("YAML: a hash comment and unquoted keywords")
    func yaml() {
        let source = "enabled: true # on purpose\nname: plain"
        #expect(text(source, .yaml, of: .keyword) == ["true"])
        #expect(text(source, .yaml, of: .comment) == ["# on purpose"])
    }

    @Test("XML: tag names carry the structure, and comments are comments")
    func xml() {
        let source = "<config name=\"a\"><!-- why --></config>"
        #expect(text(source, .xml, of: .tag) == ["<config", "</config"])
        #expect(text(source, .xml, of: .string) == ["\"a\""])
        #expect(text(source, .xml, of: .comment) == ["<!-- why -->"])
    }

    /// An apostrophe in prose must not swallow the rest of the file.
    @Test("A quote that never closes on its line is not a string")
    func unpairedQuote() {
        #expect(text("// it's fine\n$a = 1;", .php, of: .string).isEmpty)
    }

    @Test("A block comment left open still reads as a comment")
    func unterminatedBlock() {
        #expect(text("/* cut off", .php, of: .comment) == ["/* cut off"])
    }

    @Test("Languages are recognised from a fence and from a file name")
    func naming() {
        #expect(CodeLanguage.named("php") == .php)
        #expect(CodeLanguage.named("PHP") == .php)
        #expect(CodeLanguage.named("ts") == .typescript)
        #expect(CodeLanguage.named("yml") == .yaml)
        #expect(CodeLanguage.named("html") == .xml)
        // A fence can carry more than the language.
        #expect(CodeLanguage.named("php title=Example.php") == .php)
        #expect(CodeLanguage.named("") == nil)
        #expect(CodeLanguage.named(nil) == nil)
        #expect(CodeLanguage.named("brainfuck") == nil)

        #expect(CodeLanguage.forFile("src/Module/Thing.php") == .php)
        #expect(CodeLanguage.forFile("composer.json") == .json)
        #expect(CodeLanguage.forFile(".gitlab-ci.yml") == .yaml)
        #expect(CodeLanguage.forFile("Makefile") == nil)
    }
}

@Suite("Telling types from the words that direct the flow")
struct CodeTypeTests {
    private func kinds(_ source: String, _ language: CodeLanguage) -> [(String, CodeToken.Kind)] {
        SyntaxHighlighter.tokens(source, language: language).map { ($0.text, $0.kind) }
    }

    /// The line a reader most wants to read is a signature, and it is
    /// mostly types. One colour over the whole of it says nothing.
    @Test("A PHP signature is words and types, not one colour")
    func phpSignature() {
        let found = kinds("public function matches(array $row): bool", .php)
        #expect(found.contains { $0.0 == "public" && $0.1 == .keyword })
        #expect(found.contains { $0.0 == "function" && $0.1 == .keyword })
        #expect(found.contains { $0.0 == "array" && $0.1 == .type })
        #expect(found.contains { $0.0 == "bool" && $0.1 == .type })
    }

    @Test("A TypeScript signature too")
    func typescriptSignature() {
        let found = kinds("async function load(id: string): Promise<number> {", .typescript)
        #expect(found.contains { $0.0 == "async" && $0.1 == .keyword })
        #expect(found.contains { $0.0 == "string" && $0.1 == .type })
        #expect(found.contains { $0.0 == "Promise" && $0.1 == .type })
        #expect(found.contains { $0.0 == "number" && $0.1 == .type })
    }

    /// Matched as written: `String` is not `string` outside PHP, and
    /// lower-casing first would paint a variable called `Record` as a type
    /// in a language where it is not one.
    @Test("Types are matched as written, keywords however they are cased")
    func casing() {
        #expect(kinds("Promise", .typescript).first?.1 == .type)
        #expect(kinds("promise", .typescript).first?.1 == .plain)
        // PHP's keywords are case-insensitive and its types are written
        // lower case, so both still land.
        #expect(kinds("RETURN", .php).first?.1 == .keyword)
        #expect(kinds("int", .php).first?.1 == .type)
    }

    /// The words added in this pass, which were drawn plainly before.
    @Test(
        "Words that used to go unpainted are painted now",
        arguments: [
            ("require_once", CodeLanguage.php), ("isset", .php), ("endforeach", .php),
            ("satisfies", .typescript), ("keyof", .typescript), ("override", .typescript),
            ("inherit", .css), ("container", .css),
        ]
    )
    func newlyKnown(word: String, language: CodeLanguage) {
        let kind = kinds(word, language).first?.1
        #expect(kind == .keyword || kind == .type)
    }

    /// The one property every language's tests pin down: nothing is lost.
    @Test("A line with types in it still joins back into itself")
    func losesNothing() {
        for line in [
            "public function matches(array $row): bool",
            "function load(id: string): Promise<number>",
            "    $total = (int) $row['count'];",
        ] {
            for language in [CodeLanguage.php, .typescript] {
                let joined = SyntaxHighlighter.tokens(line, language: language)
                    .map(\.text).joined()
                #expect(joined == line)
            }
        }
    }
}
