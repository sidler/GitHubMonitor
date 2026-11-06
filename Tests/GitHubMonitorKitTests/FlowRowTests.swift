import Foundation
import Testing

@testable import GitHubMonitorKit

/// What a wrapping row of chips says about itself, and in particular what
/// it says when it is asked how small it could be.
///
/// Over plain sizes rather than through a window: the question is the
/// arithmetic, and the arithmetic is what went wrong. The consequence --
/// a window grown to two thousand points to honour the answer -- was
/// measured separately, through a real split view, and is written down
/// where `FlowRow.size` decides it.
@Suite("A wrapping row of chips")
struct FlowRowTests {
    private let spacing: CGFloat = 4
    private let chip = CGSize(width: 48, height: 15)

    private var strip: [CGSize] { Array(repeating: chip, count: 22) }

    /// The bug this exists for. The issue pane's header draws one chip per
    /// linked pull request, and an issue carrying twenty-two of them
    /// claimed it could not be drawn in less than twenty-two lines. AppKit
    /// honours a minimum by resizing the window, so the window grew until
    /// it ran off the screen.
    @Test("At no width it is one line tall, not one line per chip")
    func minimumIsOneLine() {
        let size = FlowRow.size(of: strip, width: 0, spacing: spacing)

        #expect(size.height == chip.height)
    }

    /// Infinity is the other degenerate proposal, and it means the
    /// opposite: all the room there is.
    @Test("Given all the room there is, everything is on one line")
    func unbounded() {
        let size = FlowRow.size(of: strip, width: .infinity, spacing: spacing)

        #expect(size.height == chip.height)
        #expect(FlowRow.lines(of: strip, width: .infinity, spacing: spacing).count == 1)
    }

    /// The mend is about the degenerate question. Given a real width it
    /// still wraps, which is the whole reason this layout exists.
    @Test("Given a width it puts what fits on a line and wraps the rest")
    func wraps() {
        // Three chips and two gaps come to 152; a fourth would not fit.
        let lines = FlowRow.lines(of: strip, width: 160, spacing: spacing)

        #expect(lines.count == 8)
        #expect(lines.first?.indices == [0, 1, 2])
        #expect(lines.last?.indices == [21])
        #expect(
            FlowRow.size(of: strip, width: 160, spacing: spacing).height
                == 8 * chip.height + 7 * spacing
        )
    }

    /// Children of different heights share a line, and the line is as tall
    /// as the tallest of them.
    @Test("A line is as tall as the tallest thing on it")
    func lineHeight() {
        let mixed = [
            CGSize(width: 40, height: 15),
            CGSize(width: 40, height: 28),
            CGSize(width: 40, height: 15),
        ]

        let lines = FlowRow.lines(of: mixed, width: 1000, spacing: spacing)

        #expect(lines.count == 1)
        #expect(lines.first?.height == 28)
    }

    /// One too wide for the row is put on a line of its own and cut to the
    /// row rather than drawn past its edge.
    @Test("Something wider than the row is cut to the row")
    func tooWide() {
        let sizes = [CGSize(width: 40, height: 15), CGSize(width: 900, height: 15)]

        let lines = FlowRow.lines(of: sizes, width: 200, spacing: spacing)

        #expect(lines.count == 2)
        #expect(lines.last?.width == 200)
        #expect(FlowRow.size(of: sizes, width: 200, spacing: spacing).width == 200)
    }

    @Test("Nothing at all is no size at all")
    func empty() {
        #expect(FlowRow.size(of: [], width: 0, spacing: spacing) == .zero)
        #expect(FlowRow.size(of: [], width: 300, spacing: spacing) == .zero)
        #expect(FlowRow.lines(of: [], width: 300, spacing: spacing).isEmpty)
    }
}
