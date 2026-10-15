import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("Standing the cards down the margin")
struct MarginCardTests {
    @Test("A card that has room stands level with its line")
    func level() {
        let tops = MarginCards.place(anchors: [40, 200, 500], heights: [60, 60, 60])
        #expect(tops == [40, 200, 500])
    }

    /// The whole reason the code can stay still: a card that grows pushes
    /// what is below it, and nothing else.
    @Test("A card too tall for its gap pushes the next one down")
    func pushes() {
        let tops = MarginCards.place(anchors: [40, 80], heights: [200, 60], gap: 8)
        #expect(tops == [40, 248])
    }

    @Test("The push carries on down the column")
    func carriesOn() {
        let tops = MarginCards.place(anchors: [0, 10, 20], heights: [100, 100, 100], gap: 10)
        #expect(tops == [0, 110, 220])
    }

    /// A card never rises to meet a gap above it. It would then stand
    /// beside a line it is not about, which is worse than standing low.
    @Test("A card never moves up to its line, only down away from it")
    func neverUp() {
        let tops = MarginCards.place(anchors: [300, 50], heights: [20, 20], gap: 4)
        #expect(tops[0] == 300)
        #expect(tops[1] == 324)
    }

    @Test("Nothing to place is no column at all")
    func empty() {
        #expect(MarginCards.place(anchors: [], heights: []).isEmpty)
        #expect(MarginCards.height(tops: [], heights: []) == 0)
    }

    /// Heights arrive a frame after the cards do. Until then the column
    /// still has to put them somewhere rather than crash.
    @Test("A card whose height is not known yet is still placed")
    func unmeasured() {
        let tops = MarginCards.place(anchors: [10, 20], heights: [])
        #expect(tops == [10, 20])
    }

    @Test("The column is as tall as its lowest card's bottom edge")
    func tall() {
        let tops = MarginCards.place(anchors: [0, 300], heights: [40, 90])
        #expect(MarginCards.height(tops: tops, heights: [40, 90]) == 390)
    }

    /// A card hanging off the first line must not start above the column.
    @Test("Nothing is placed above where the column begins")
    func floor() {
        let tops = MarginCards.place(anchors: [0], heights: [40], from: 12)
        #expect(tops == [12])
    }
}

@Suite("What belongs at a file's margin")
@MainActor
struct MarginEntryTests {
    private func thread(_ id: String, line: Int, resolved: Bool = false) -> ReviewThread {
        ReviewThread(
            id: id, path: "a.swift", line: line, side: .new,
            isResolved: resolved, isOutdated: false, comments: []
        )
    }

    @Test("Conversations and unsent remarks, in the order the file runs")
    func ordered() {
        let entries = MarginEntry.all(
            threads: [thread("late", line: 40), thread("early", line: 4)],
            draft: [DraftComment(path: "a.swift", line: 20, body: "mid")],
            editing: DraftTarget(),
            path: "a.swift"
        )
        #expect(entries.count == 3)
        #expect(entries.first?.id == MarginEntry.key(forThread: "early"))
        #expect(entries.last?.id == MarginEntry.key(forThread: "late"))
    }

    /// A reply is drawn inside the conversation it answers. Giving it a
    /// card of its own would say it on the line twice.
    @Test("A reply gets no card of its own")
    func replies() {
        let entries = MarginEntry.all(
            threads: [thread("t1", line: 4)],
            draft: [
                DraftComment(path: "a.swift", line: 4, replyTo: "t1", body: "answer")
            ],
            editing: DraftTarget(),
            path: "a.swift"
        )
        #expect(entries.count == 1)
        #expect(entries.first?.id == MarginEntry.key(forThread: "t1"))
    }

    @Test("The open box is a card, at the line it is about")
    func editor() {
        let target = DraftTarget()
        target.open(line: 12, side: .new)
        let entries = MarginEntry.all(
            threads: [], draft: [], editing: target, path: "a.swift"
        )
        #expect(entries.map(\.id) == [MarginEntry.editorKey])
    }

    /// Reworded, it is drawn in the card the remark already has; and a
    /// reply is drawn in its conversation. Either way a second box would
    /// be a second place to type the same thing.
    @Test("A box reworking a remark, or answering a thread, is not its own card")
    func noDoubleBox() {
        let remark = DraftComment(path: "a.swift", line: 12, body: "said")
        let editing = DraftTarget()
        editing.open(line: 12, side: .new, text: "said", editing: remark.id)
        #expect(
            MarginEntry.all(threads: [], draft: [remark], editing: editing, path: "a.swift")
                .map(\.id) == [MarginEntry.key(forRemark: remark.id)]
        )

        let replying = DraftTarget()
        replying.open(reply: thread("t1", line: 4))
        #expect(
            MarginEntry.all(
                threads: [thread("t1", line: 4)], draft: [], editing: replying, path: "a.swift"
            ).map(\.id) == [MarginEntry.key(forThread: "t1")]
        )
    }

    @Test("A settled conversation is a card like any other")
    func settled() {
        let entries = MarginEntry.all(
            threads: [thread("done", line: 4, resolved: true)],
            draft: [], editing: DraftTarget(), path: "a.swift"
        )
        #expect(entries.count == 1)
    }
}
