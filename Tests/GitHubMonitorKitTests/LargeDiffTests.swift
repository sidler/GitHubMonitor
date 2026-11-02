import Foundation
import Testing
@testable import GitHubMonitorKit

@MainActor
@Suite("A review nobody would enjoy")
struct LargeDiffTests {
    /// The size that prompted this: forty-three files and a couple of
    /// thousand changed lines, several hunks apiece. One hunk per file hid
    /// the thing that mattered, which is how many separately scrolling
    /// columns the two-column layout ends up drawing.
    ///
    /// And one file of the other shape, added later: two thousand lines of
    /// patch in a single hunk. Forty-three middling files say nothing
    /// about one enormous one, which is the case that juddered.
    @Test("The sample is the size it is meant to be")
    func shape() {
        let files = SampleData.largeDiff()
        #expect(files.count == 44)
        #expect(files.contains { $0.path == SampleData.hugeFile().path })

        let lines = files.reduce(0) { $0 + ($1.patch?.components(separatedBy: "\n").count ?? 0) }
        #expect(lines > 1500)

        let hunks = files.reduce(0) { total, file in
            total + (file.patch?.components(separatedBy: "\n").count { $0.hasPrefix("@@") } ?? 0)
        }
        #expect(hunks > 100)

        // Every file is one the diff can actually draw.
        for file in files {
            #expect(file.patch?.isEmpty == false)
            #expect(file.path.hasSuffix(".php"))
        }
    }

    /// Opening a diff this size works everything out once; scrolling it
    /// must not work any of it out again. The second pass is the one that
    /// has to be quick, because it is the one that happens per frame.
    @Test("Working it out once is enough")
    func keptBetweenFrames() {
        let files = SampleData.largeDiff()
        DiffCache.shared.forget()

        let coldStart = Date()
        for file in files {
            _ = DiffCache.shared.rows(of: file.patch!)
            _ = DiffCache.shared.emphasis(in: file.patch!)
        }
        let cold = Date().timeIntervalSince(coldStart)

        // Four passes over every file, which is more than any one frame
        // asks for.
        let warmStart = Date()
        for _ in 0..<4 {
            for file in files {
                _ = DiffCache.shared.rows(of: file.patch!)
                _ = DiffCache.shared.emphasis(in: file.patch!)
            }
        }
        let warm = Date().timeIntervalSince(warmStart) / 4

        #expect(warm < cold / 20)
        // And in absolute terms, comfortably inside a frame at 60fps.
        #expect(warm < 0.016)
    }

    /// The alignment is quadratic in the size of a changed block, so a
    /// review of this size is where that would show. A guard rather than a
    /// measurement: the bound is loose enough to pass on a loaded machine.
    @Test("The whole review aligns in well under a second")
    func alignmentCost() {
        let files = SampleData.largeDiff()
        let started = Date()
        for file in files { _ = DiffAlignment.emphasis(in: file.patch!) }
        #expect(Date().timeIntervalSince(started) < 1.0)
    }

    /// Two columns draw one pair of scrolling views per block, and a block
    /// ends at every hunk header. A file of many hunks is therefore a file
    /// of many scroll views, which is what makes this worth counting.
    @Test("The blocks a file is cut into follow its hunks")
    func blocksPerFile() {
        // The huge file is deliberately one hunk: its point is length,
        // not how many pieces it falls into.
        let refactoring = SampleData.largeDiff().filter {
            $0.path != SampleData.hugeFile().path
        }
        for file in refactoring {
            let rows = DiffSideBySide.rows(of: file.patch!)
            let hunks = rows.count { if case .hunk = $0 { return true } else { return false } }
            #expect(hunks >= 3)

            // Every line of the patch appears exactly once across the rows
            // and no more: a context line stands on both sides but is one
            // line, a removal and the addition answering it are two.
            var accounted = 0
            for row in rows {
                switch row {
                case .hunk, .note:
                    accounted += 1
                case .pair(let left, let right):
                    let isContext = left.map { !$0.text.hasPrefix("-") } ?? false
                        && right.map { !$0.text.hasPrefix("+") } ?? false
                    accounted += isContext ? 1 : (left == nil ? 0 : 1) + (right == nil ? 0 : 1)
                }
            }
            #expect(accounted == file.patch!.components(separatedBy: "\n").count)
        }
    }
}

/// The single enormous file, which is a different shape of problem from
/// forty-three middling ones.
@MainActor
@Suite("One very large file")
struct HugeFileTests {
    @Test("Two thousand lines of patch with a thousand changes in them")
    func size() {
        let file = SampleData.hugeFile()
        let rows = file.patch?.components(separatedBy: "\n") ?? []
        #expect(rows.count > 2000)
        #expect(rows.count { $0.hasPrefix("+") } == 1000)
        #expect(rows.count { $0.hasPrefix("-") } == 1000)
        #expect(file.additions == 1000)
        #expect(file.deletions == 1000)
    }

    /// Everything a view body asks for comes from the cache after the
    /// first time, which is what keeps a scroll from repeating the work.
    @Test("Every reading of it is cached")
    func cached() {
        let patch = SampleData.hugeFile().patch!
        DiffCache.shared.forget()

        let numbers = DiffCache.shared.numbers(of: patch)
        let marks = DiffCache.shared.emphasis(in: patch)
        let comments = DiffCache.shared.comments(in: patch, language: .php)
        let built = DiffCache.shared.lines(of: patch, language: .php) {
            [PatchLine(
                id: 0, text: "x", insideHunk: true, number: .none,
                emphasis: [], insideComment: false
            )]
        }

        // Asked again, the same answers come back without being worked
        // out a second time -- which the line array proves by building
        // something different if it is asked to build at all.
        #expect(DiffCache.shared.numbers(of: patch).count == numbers.count)
        #expect(DiffCache.shared.emphasis(in: patch).count == marks.count)
        #expect(
            DiffCache.shared.comments(in: patch, language: .php)
                .isInsideComment(line: 1, side: .new) == comments.isInsideComment(line: 1, side: .new)
        )
        #expect(
            DiffCache.shared.lines(of: patch, language: .php) { [] }.count == built.count
        )
    }
}
