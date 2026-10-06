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
