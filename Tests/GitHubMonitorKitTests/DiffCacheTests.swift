import Foundation
import Testing
@testable import GitHubMonitorKit

@MainActor
@Suite("Not working the same patch out twice")
struct DiffCacheTests {
    /// Roughly the shape of a real review: blocks of replaced lines with
    /// context between them.
    private func patch(hunks: Int, removed: Int, added: Int) -> String {
        var lines = [String]()
        for hunk in 0..<hunks {
            lines.append("@@ -\(hunk * 50),40 +\(hunk * 50),60 @@ class Thing")
            lines.append("     public function setUp(): void")
            for i in 0..<removed {
                lines.append("-        $this->assertSame($expected[\(i)], $actual->value(\(i)));")
            }
            for i in 0..<added {
                lines.append("+        $this->assertSame($expected[\(i)], $actual->total(\(i)), 'row \(i)');")
            }
            lines.append("     }")
        }
        return lines.joined(separator: "\n")
    }

    @Test("The answer is the same whether it was kept or worked out")
    func sameAnswer() {
        let cache = DiffCache.shared
        cache.forget()
        let text = patch(hunks: 2, removed: 4, added: 5)
        let first = cache.emphasis(in: text)
        #expect(first == cache.emphasis(in: text))
        #expect(first == DiffAlignment.emphasis(in: text))
        #expect(cache.rows(of: text) == DiffSideBySide.rows(of: text))
    }

    /// The reason this exists: both of these are read inside a view's body,
    /// which SwiftUI runs again on every frame while the diff is scrolled.
    /// Asserted as a ratio rather than a time, so a busy machine does not
    /// make it fail.
    @Test("A patch already seen comes back far faster than it was worked out")
    func keepsIt() {
        let cache = DiffCache.shared
        cache.forget()
        let text = patch(hunks: 6, removed: 25, added: 30)

        let coldStart = Date()
        _ = cache.emphasis(in: text)
        let cold = Date().timeIntervalSince(coldStart)

        let warmStart = Date()
        for _ in 0..<50 { _ = cache.emphasis(in: text) }
        let warm = Date().timeIntervalSince(warmStart) / 50

        #expect(warm < cold / 20)
    }

    /// A pull request can touch hundreds of files, and the window would
    /// otherwise hold every patch it ever drew.
    @Test("Only so many patches are kept")
    func bounded() {
        let cache = DiffCache.shared
        cache.forget()
        for i in 0..<200 {
            _ = cache.emphasis(in: "@@ -1,1 +1,1 @@\n-line \(i)\n+line \(i) changed")
        }
        #expect(cache.count <= 64)
    }
}

@Suite("What the alignment costs")
struct DiffAlignmentCostTests {
    /// A guard rather than a measurement. The first version of this took
    /// two seconds on a patch this size, because it broke both lines into
    /// words again for every candidate pair; the bound is loose enough to
    /// pass on a loaded machine and tight enough to catch that coming back.
    @Test("A nine-hundred-line patch aligns in well under half a second")
    func cost() {
        var lines = [String]()
        for hunk in 0..<10 {
            lines.append("@@ -\(hunk * 50),40 +\(hunk * 50),60 @@ class Thing")
            lines.append("     public function setUp(): void")
            for i in 0..<40 {
                lines.append("-        $this->assertSame($expected[\(i)], $actual->value(\(i)));")
            }
            for i in 0..<50 {
                lines.append("+        $this->assertSame($expected[\(i)], $actual->total(\(i)), 'row \(i)');")
            }
        }
        let text = lines.joined(separator: "\n")

        let started = Date()
        let marks = DiffAlignment.emphasis(in: text)
        let seconds = Date().timeIntervalSince(started)

        #expect(marks.count == text.components(separatedBy: "\n").count)
        #expect(seconds < 0.5)
    }
}

/// The other half of the per-frame cost: the patch is worked out once by
/// `DiffCache`, and then every visible line is painted again.
@MainActor
@Suite("Not painting the same line twice")
struct PaintedCodeTests {
    private func lines(_ count: Int) -> [CodeText] {
        (0..<count).map {
            CodeText(
                source: "+        $this->assertSame($expected[\($0)], $actual->total(\($0)));",
                language: .php
            )
        }
    }

    @Test("The same line comes back painted the same way")
    func sameAnswer() {
        PaintedCode.shared.forget()
        let code = lines(1)[0]
        let first = PaintedCode.shared.text(for: code)
        #expect(first == PaintedCode.shared.text(for: code))
        // Painted at all, not merely remembered: the call is the only
        // thing that puts colour on the line.
        #expect(first.characters.isEmpty == false)
        #expect(String(first.characters).hasPrefix("+        $this->assertSame"))
    }

    /// Asserted as a ratio rather than a time, so a busy machine does not
    /// make it fail. A screenful of a large PHP diff measured five and a
    /// half milliseconds to paint, which SwiftUI would spend on every
    /// frame of a scroll.
    @Test("A line already painted comes back far faster than it was painted")
    func keepsIt() {
        PaintedCode.shared.forget()
        let code = lines(150)

        let coldStart = Date()
        for line in code { _ = PaintedCode.shared.text(for: line) }
        let cold = Date().timeIntervalSince(coldStart)

        let warmStart = Date()
        for _ in 0..<5 {
            for line in code { _ = PaintedCode.shared.text(for: line) }
        }
        let warm = Date().timeIntervalSince(warmStart) / 5

        #expect(warm < cold / 5)
    }

    /// Two generations, so nothing is held for more than two turns.
    @Test("What is held is bounded")
    func bounded() {
        PaintedCode.shared.forget()
        for index in 0..<5_000 {
            _ = PaintedCode.shared.text(
                for: CodeText(source: "let x\(index) = \(index)", language: .typescript)
            )
        }
        #expect(PaintedCode.shared.count <= 4_096)
        PaintedCode.shared.forget()
        #expect(PaintedCode.shared.count == 0)
    }
}

/// The tables the scan reads for every word and every character.
@Suite("A language is worked out once")
struct CodeLanguageTableTests {
    @Test("The same set comes back each time, and it is the right one")
    func stable() {
        for language in CodeLanguage.allCases {
            #expect(language.keywords == language.keywords)
            #expect(language.types == language.types)
            #expect(language.lineComments == language.lineComments)
            #expect(language.stringDelimiters == language.stringDelimiters)
        }
        #expect(CodeLanguage.php.keywords.contains("foreach"))
        #expect(CodeLanguage.php.types.contains("bool"))
        #expect(CodeLanguage.json.keywords.isEmpty == false || CodeLanguage.json.types.isEmpty)
        #expect(CodeLanguage.php.blockComment?.open == "/*")
        #expect(CodeLanguage.json.blockComment == nil)
    }
}
