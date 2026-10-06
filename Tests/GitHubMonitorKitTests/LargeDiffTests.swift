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
    @Test("The sample is the size it is meant to be")
    func shape() {
        let files = SampleData.largeDiff()
        #expect(files.count == 43)

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
        for file in SampleData.largeDiff() {
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
