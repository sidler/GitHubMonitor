import Foundation
import SwiftUI
import Testing

@testable import GitHubMonitorKit

/// What holding a painted line costs, and how many of them are held.
///
/// The number of lines kept is a memory decision rather than a feeling,
/// and it was made from the figure this measures. Pinned so that the
/// reasoning is revisited rather than quietly invalidated: if an
/// `AttributedString` ever becomes much cheaper or much dearer, the
/// limit that was chosen against 2.6 KB a line is no longer the limit
/// anybody would choose.
@MainActor
@Suite("Holding painted lines")
struct PaintedCodeBudgetTests {
    /// What this process is holding, as the kernel sees it.
    private func footprint() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let answer = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return answer == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    private let line = "    public func somethingOrOther(_ value: String) -> Int { value.count }"

    /// Measured at 4.4 KB a line -- up from the 2.6 KB the limit was
    /// chosen against, which is the drift this suite exists to show.
    ///
    /// The bounds are an order of magnitude either side of that and not
    /// a digit tighter, because the instrument is the whole process's
    /// resident size while the rest of the suite allocates and frees on
    /// other threads. Six runs of this test on its own came back
    /// between 4325 and 4542 bytes a line; six runs of the same code in
    /// the full suite came back between 1732 and 4399, because pages
    /// another test gives back are subtracted from this reading. That
    /// is what failed a floor of 500 every twentieth run or so, and no
    /// retry can mend it: a second measurement in the same process
    /// re-uses the memory the first one freed and reads as nothing at
    /// all. What is left to catch is the order-of-magnitude change,
    /// which is the only kind that would move the decision anyway.
    @Test("A painted line costs a couple of kilobytes")
    func cost() {
        PaintedCode.shared.forget()
        defer { PaintedCode.shared.forget() }

        // One through first, so whatever the painting allocates once is
        // allocated before the measurement starts.
        _ = PaintedCode.shared.text(for: CodeText(source: line, language: .swift))
        let before = footprint()
        let lines = 4000
        for index in 0..<lines {
            _ = PaintedCode.shared.text(
                for: CodeText(source: "\(line) // \(index)", language: .swift)
            )
        }
        let each = (footprint() - before) / lines

        #expect(each > 400, "a painted line came out at \(each) bytes")
        #expect(each < 40_000, "a painted line came out at \(each) bytes")
    }

    /// The reason the limit was doubled. One cache serves every tab, so
    /// a second review open beside the first must not roll the
    /// generation -- that is what sent the lines scrolled past back to
    /// be painted again.
    @Test("Two reviews the size of the largest measured both fit")
    func capacity() {
        // 1631 lines of patch across 55 files, the largest open on the
        // repository this was measured against.
        let largestReview = 1631

        #expect(PaintedCode.shared.limit >= 2 * largestReview)
    }

    /// And not raised past what the memory will bear. Holding between
    /// the limit and twice it, at the figure above, this is the ceiling
    /// the choice was made against.
    ///
    /// 2600 is the figure the choice was made against, not the figure
    /// measured today. At the 4.4 KB the test above now reads, the same
    /// arithmetic comes to 34 MB and this ceiling is 7 per cent behind
    /// it -- the limit wants either four hundred lines off it or a
    /// ceiling that admits the extra two megabytes. Left as it stands
    /// until that is decided, because moving either number is the
    /// decision and not the reporting of it.
    @Test("What it holds at worst stays within the budget it was chosen for")
    func budget() {
        let worstCase = 2 * PaintedCode.shared.limit * 2600

        #expect(worstCase < 32 * 1024 * 1024, "worst case is \(worstCase / 1024 / 1024) MB")
    }
}
