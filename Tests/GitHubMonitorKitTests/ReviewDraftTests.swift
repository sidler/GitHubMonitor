import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("A review somebody is part way through writing")
struct ReviewDraftTests {
    private func comment(
        _ path: String = "a.swift", line: Int = 10, body: String = "look here"
    ) -> DraftComment {
        DraftComment(path: path, line: line, body: body)
    }

    @Test("Remarks on one file run down it in order")
    func inOrder() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        draft.add(comment(line: 30))
        draft.add(comment(line: 10))
        draft.add(comment("b.swift", line: 1))

        #expect(draft.comments(in: "a.swift").map(\.line) == [10, 30])
        #expect(draft.comments(in: "b.swift").count == 1)
        #expect(draft.comments(in: "c.swift").isEmpty)
    }

    /// A remark with nothing left in it is not a remark. GitHub would
    /// refuse it, and leaving it would send somebody an empty comment
    /// with their name on it.
    @Test("Rubbing out the words removes the remark")
    func emptied() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        let one = comment()
        draft.add(one)
        draft.change(one.id, to: "   \n ")

        #expect(draft.isEmpty)
    }

    @Test("Changing the words keeps everything else about it")
    func changed() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        let one = comment(line: 42)
        draft.add(one)
        draft.change(one.id, to: "  on second thoughts  ")

        #expect(draft.comments.first?.body == "on second thoughts")
        #expect(draft.comments.first?.line == 42)
        #expect(draft.comments.first?.id == one.id)
    }

    @Test("Changing one that is not there changes nothing")
    func unknown() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        draft.add(comment())
        draft.change(UUID(), to: "")

        #expect(draft.comments.count == 1)
    }

    @Test("What the button will say")
    func summary() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        draft.add(comment())
        #expect(draft.summary == "1 remark")
        draft.add(comment(line: 11))
        #expect(draft.summary == "2 remarks")
    }
}

@Suite("Keeping a half-written review between sittings")
struct DraftStoreTests {
    private func store() -> DraftStore {
        DraftStore(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ghm-drafts-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func draft(_ id: String = "PR_1", body: String = "look here") -> ReviewDraft {
        var draft = ReviewDraft(pullRequestID: id, commit: "abc")
        draft.add(DraftComment(path: "a.swift", line: 10, side: .new, body: body))
        return draft
    }

    /// The whole reason it is on disk: review remarks are the most
    /// expensive thing anybody produces in front of this window.
    @Test("What was written is still there afterwards")
    func roundTrip() {
        let store = store()
        store.save(draft())

        let read = store.load(pullRequestID: "PR_1")
        #expect(read?.comments.first?.body == "look here")
        #expect(read?.comments.first?.line == 10)
        #expect(read?.comments.first?.side == .new)
        #expect(read?.commit == "abc")
    }

    @Test("Nothing written, nothing to read")
    func nothingThere() {
        #expect(store().load(pullRequestID: "PR_1") == nil)
    }

    /// An empty draft on disk is a file saying somebody is in the middle
    /// of something when they are not.
    @Test("Emptying it takes the file away")
    func emptied() {
        let store = store()
        store.save(draft())
        store.save(ReviewDraft(pullRequestID: "PR_1", commit: "abc"))

        #expect(store.load(pullRequestID: "PR_1") == nil)
        #expect(store.all().isEmpty)
    }

    @Test("Sending it is what throws it away")
    func removed() {
        let store = store()
        store.save(draft())
        store.remove(pullRequestID: "PR_1")

        #expect(store.load(pullRequestID: "PR_1") == nil)
    }

    /// Half of somebody's review is worse than none of it, because they
    /// would not know which half.
    @Test("A file of an older shape is ignored rather than half-read")
    func oldShape() {
        let store = store()
        var old = draft()
        old.schema = ReviewDraft.currentSchema + 1
        store.save(old)

        #expect(store.load(pullRequestID: "PR_1") == nil)
    }

    @Test("A file that belongs to another pull request is not handed over")
    func wrongOwner() {
        let store = store()
        store.save(draft("PR_2"))

        #expect(store.load(pullRequestID: "PR_1") == nil)
        #expect(store.load(pullRequestID: "PR_2") != nil)
    }

    @Test("Everything half written comes back when the app does")
    func all() {
        let store = store()
        store.save(draft("PR_1"))
        store.save(draft("PR_2"))

        #expect(Set(store.all().map(\.pullRequestID)) == ["PR_1", "PR_2"])
    }

    /// A node id carries characters a path cannot.
    @Test("An id that is not a file name becomes one")
    func slug() {
        let store = store()
        store.save(draft("PR_kwDOA/b+c="))

        #expect(store.load(pullRequestID: "PR_kwDOA/b+c=")?.comments.count == 1)
    }
}
