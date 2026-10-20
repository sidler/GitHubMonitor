import Testing
@testable import GitHubMonitorKit

/// Whether a conversation on a diff is drawn open.
///
/// Two things move it and they do not have equal say: the resolved mark
/// puts the fold where a freshly drawn diff would have put it, and a
/// press of the header overrules that until the resolved mark changes
/// again. Tested here rather than looked at, because the case that was
/// wrong -- settling a conversation while reading it -- is the one that
/// needs a click in a diff nothing can click in.
@Suite("Folding a conversation")
@MainActor
struct ThreadFoldTests {
    @Test("A conversation that arrives settled is drawn shut")
    func settledArrival() {
        #expect(ThreadFold(isResolved: true).isExpanded == false)
    }

    @Test("A conversation that arrives unsettled is drawn open")
    func unsettledArrival() {
        #expect(ThreadFold(isResolved: false).isExpanded == true)
    }

    @Test("Settling one that is being read folds it away")
    func settling() {
        let fold = ThreadFold(isResolved: false)
        fold.settled(resolved: true)
        #expect(fold.isExpanded == false)
    }

    @Test("Unsettling one that is folded opens it again")
    func unsettling() {
        let fold = ThreadFold(isResolved: true)
        fold.settled(resolved: false)
        #expect(fold.isExpanded == true)
    }

    @Test("The header still opens and shuts it afterwards")
    func headerWins() {
        let fold = ThreadFold(isResolved: false)
        fold.settled(resolved: true)
        fold.toggle()
        #expect(fold.isExpanded == true)
        fold.toggle()
        #expect(fold.isExpanded == false)
    }

    @Test("A redraw that says nothing new leaves it where it was put")
    func redraw() {
        let fold = ThreadFold(isResolved: true)
        fold.toggle()
        fold.settled(resolved: true)
        #expect(fold.isExpanded == true)
    }

    @Test("Settling it again after it was opened by hand folds it once more")
    func settlingTwice() {
        let fold = ThreadFold(isResolved: false)
        fold.settled(resolved: true)
        fold.toggle()
        fold.settled(resolved: false)
        fold.settled(resolved: true)
        #expect(fold.isExpanded == false)
    }
}
