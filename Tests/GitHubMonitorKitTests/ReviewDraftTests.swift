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

    /// For the tree beside the diff. Your own unsent remarks are as good
    /// a reason to go back to a file as anybody else's conversation, and
    /// until now the tree said nothing about them.
    @Test("The draft counts its remarks per file")
    func perFile() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        draft.add(comment(line: 30))
        draft.add(comment(line: 10))
        draft.add(comment("b.swift", line: 1))

        #expect(draft.countsByPath == ["a.swift": 2, "b.swift": 1])
    }

    /// A file nobody has written about is absent rather than nought, so
    /// the tree can ask whether there is a mark at all.
    @Test("A draft with nothing in it counts nothing")
    func noneAtAll() {
        #expect(ReviewDraft(pullRequestID: "PR_1", commit: "abc").countsByPath.isEmpty)
    }

    /// A reply is a remark you have not sent either, and it stands on the
    /// file it answers.
    @Test("Replies are counted with the remarks that open a conversation")
    func repliesCount() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        draft.add(comment(line: 10))
        draft.add(
            DraftComment(path: "a.swift", line: 12, replyTo: "T_1", body: "agreed")
        )
        #expect(draft.countsByPath == ["a.swift": 2])
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

    /// The one question the Request changes button asks.
    ///
    /// A remark for the conversation goes out as a comment beside the
    /// review, never within it -- so a draft holding only that leaves
    /// the review with no words, and GitHub refuses a change request
    /// that has none. A button that went by "something is written"
    /// posted the remark and then failed on the review behind it, with
    /// nothing left to try again.
    @Test("A conversation remark alone is not something a review can carry")
    func reviewWords() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        #expect(draft.hasReviewWords == false)

        draft.conversation = "a word for everybody reading"
        #expect(draft.isEmpty == false)
        #expect(draft.hasReviewWords == false)

        draft.body = "   "
        #expect(draft.hasReviewWords == false, "blank is not a body")

        draft.body = "and one about the whole"
        #expect(draft.hasReviewWords)

        var onLines = ReviewDraft(pullRequestID: "PR_2", commit: "abc")
        onLines.add(comment())
        #expect(onLines.hasReviewWords)
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

/// Sending a review: what goes with it, and how it is worded before it
/// goes.
@Suite("Sending a review")
struct ReviewSubmissionTests {
    private let comments = [
        DraftComment(path: "a.swift", line: 10, side: .new, body: "this leaks"),
        DraftComment(path: "b.swift", line: 3, side: .old, body: "why was this removed?"),
    ]

    /// The remarks travel with the review rather than being attached one
    /// at a time to a pending review, so it either happens or does not.
    @Test("The remarks are part of the one request")
    func oneRequest() {
        #expect(ApprovalQuery.submitDocument.contains("threads: $threads"))
        #expect(ApprovalQuery.submitDocument.contains("addPullRequestReview"))
        #expect(!ApprovalQuery.submitDocument.contains("addPullRequestReviewThread"))
    }

    /// Which file a line belongs to: the new one for nearly everything,
    /// the old one for a remark on a line that was removed.
    @Test("Each remark says where it goes")
    func shape() {
        let threads = ApprovalQuery.threads(from: comments)
        #expect(threads.count == 2)
        #expect(threads[0]["path"] as? String == "a.swift")
        #expect(threads[0]["line"] as? Int == 10)
        #expect(threads[0]["side"] as? String == "RIGHT")
        #expect(threads[0]["body"] as? String == "this leaks")
        #expect(threads[1]["side"] as? String == "LEFT")
    }

    @Test("Nothing written, nothing attached")
    func empty() {
        #expect(ApprovalQuery.threads(from: []).isEmpty)
    }

    /// An approval says something by itself. A review that neither
    /// approves nor objects and carries no remarks is an empty envelope.
    @Test("Only an approval is worth sending on its own")
    func standsAlone() {
        #expect(ApprovalQuery.Event.approve.standsAlone)
        #expect(!ApprovalQuery.Event.comment.standsAlone)
        #expect(!ApprovalQuery.Event.requestChanges.standsAlone)
    }

    @Test("The question says how many remarks go with it")
    func wording() {
        let one = ApprovalQuery.confirmation(
            repository: "octo/platform", number: 7, isAutoMergeArmed: false, remarks: 1
        )
        #expect(one.contains("One remark goes with it"))

        let several = ApprovalQuery.confirmation(
            repository: "octo/platform", number: 7, isAutoMergeArmed: false, remarks: 3
        )
        #expect(several.contains("3 remarks go with it"))

        let none = ApprovalQuery.confirmation(
            repository: "octo/platform", number: 7, isAutoMergeArmed: false
        )
        #expect(!none.contains("remark"))
    }

    @Test("And what it is: approving, objecting, or neither")
    func verdict() {
        let changes = ApprovalQuery.confirmation(
            repository: "octo/platform", number: 7, isAutoMergeArmed: false,
            event: .requestChanges, remarks: 1
        )
        #expect(changes.contains("Asking for changes"))
        #expect(!changes.contains("An approval"))
    }

    /// Armed auto-merge is only worth warning about for the one event
    /// that can set it off.
    @Test("The auto-merge warning belongs to approving alone")
    func autoMerge() {
        #expect(
            ApprovalQuery.confirmation(
                repository: "o/p", number: 1, isAutoMergeArmed: true, event: .approve
            ).contains("Auto-merge")
        )
        #expect(
            !ApprovalQuery.confirmation(
                repository: "o/p", number: 1, isAutoMergeArmed: true, event: .comment
            ).contains("Auto-merge")
        )
    }
}

/// Moving a file at a time through a diff.
@Suite("Paging through the files of a diff")
struct DiffPagerTests {
    private func files(_ names: String...) -> [ChangedFile] {
        names.map {
            ChangedFile(path: $0, additions: 1, deletions: 0, change: .modified, patch: "@@")
        }
    }

    private var three: [ChangedFile] { files("a.swift", "b.swift", "c.swift") }

    /// Counted over all of them, ticked or not: a number that depended on
    /// what somebody had already read would be a number nobody could use.
    @Test("Where the pager stands, out of how many")
    func place() {
        #expect(DiffPager.place(of: "b.swift", in: three)?.at == 2)
        #expect(DiffPager.place(of: "b.swift", in: three)?.of == 3)
        // Nothing read yet is the first of them, not nowhere.
        #expect(DiffPager.place(of: nil, in: three)?.at == 1)
        #expect(DiffPager.place(of: "gone.swift", in: three)?.at == 1)
        #expect(DiffPager.place(of: "a.swift", in: []) == nil)
    }

    /// No wrapping. A diff has a first file and a last one, and
    /// pretending otherwise loses the one thing a pager is for.
    @Test("The arrows stop at both ends")
    func ends() {
        #expect(DiffPager.file(before: "a.swift", in: three) == nil)
        #expect(DiffPager.file(after: "c.swift", in: three) == nil)
        #expect(DiffPager.file(before: "b.swift", in: three) == "a.swift")
        #expect(DiffPager.file(after: "b.swift", in: three) == "c.swift")
    }

    @Test("From nowhere, forward is the first file")
    func fromNowhere() {
        #expect(DiffPager.file(after: nil, in: three) == "a.swift")
        #expect(DiffPager.file(before: nil, in: three) == nil)
    }

    @Test("What a paging diff draws")
    func shown() {
        #expect(DiffPager.shown("b.swift", in: three)?.path == "b.swift")
        #expect(DiffPager.shown(nil, in: three)?.path == "a.swift")
        // A file that has gone -- a reload can replace them underneath a
        // diff -- falls back to the first rather than to nothing.
        #expect(DiffPager.shown("gone.swift", in: three)?.path == "a.swift")
        #expect(DiffPager.shown("a.swift", in: []) == nil)
    }

    /// Two questions, not one: how many columns a patch has and how many
    /// files are on screen are decided separately.
    @Test("Paging and layout are separate")
    func separate() {
        #expect(DiffPaging.allCases.count == 2)
        #expect(DiffPaging.scroll.label != DiffPaging.oneFile.label)
        #expect(DiffPaging.scroll.symbolName != DiffPaging.oneFile.symbolName)
    }
}

/// Answering a conversation somebody else began.
@Suite("A review that answers somebody")
struct ReviewReplyTests {
    private func opening(_ line: Int = 10) -> DraftComment {
        DraftComment(path: "a.swift", line: line, body: "this leaks")
    }

    private func reply(to thread: String, _ body: String = "fixed") -> DraftComment {
        DraftComment(path: "a.swift", line: 10, replyTo: thread, body: body)
    }

    @Test("A reply knows the conversation it belongs to")
    func knowsItsThread() {
        #expect(reply(to: "PRRT_1").isReply)
        #expect(!opening().isReply)
        #expect(reply(to: "PRRT_1").replyTo == "PRRT_1")
    }

    /// A draft written before replies existed decodes with none: the
    /// missing field reads as nil, which is exactly what those are.
    @Test("An older draft still reads, as a draft of openings")
    func olderDraft() throws {
        let json = """
            {
              "schema": 1,
              "pullRequestID": "PR_1",
              "commit": "abc",
              "comments": [
                {
                  "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
                  "path": "a.swift",
                  "line": 10,
                  "side": "new",
                  "body": "look here",
                  "writtenAt": "2026-10-15T09:00:00Z"
                }
              ]
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let draft = try decoder.decode(ReviewDraft.self, from: Data(json.utf8))

        #expect(draft.comments.count == 1)
        #expect(draft.comments.first?.replyTo == nil)
        #expect(!draft.needsPendingReview)
    }

    /// The common draft keeps the single request it always had; only one
    /// with replies in it pays for the detour through a pending review.
    @Test("Only a draft with replies takes the long way")
    func whenTheDetourIsNeeded() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        draft.add(opening())
        #expect(!draft.needsPendingReview)

        draft.add(reply(to: "PRRT_1"))
        #expect(draft.needsPendingReview)
        #expect(draft.openings.count == 1)
        #expect(draft.replies.count == 1)
    }

    @Test("What a draft answers one conversation with, oldest first")
    func perThread() {
        var draft = ReviewDraft(pullRequestID: "PR_1", commit: "abc")
        let later = DraftComment(
            path: "a.swift", line: 10, replyTo: "PRRT_1", body: "and another thing",
            writtenAt: Date(timeIntervalSince1970: 200)
        )
        let earlier = DraftComment(
            path: "a.swift", line: 10, replyTo: "PRRT_1", body: "fixed",
            writtenAt: Date(timeIntervalSince1970: 100)
        )
        draft.add(later)
        draft.add(earlier)
        draft.add(reply(to: "PRRT_2"))

        #expect(draft.replies(to: "PRRT_1").map(\.body) == ["fixed", "and another thing"])
        #expect(draft.replies(to: "PRRT_2").count == 1)
        #expect(draft.replies(to: "PRRT_9").isEmpty)
    }

    @Test("The long way round is three mutations, named")
    func documents() {
        #expect(ApprovalQuery.pendingDocument.contains("addPullRequestReview"))
        // No event, which is what leaves it pending.
        #expect(!ApprovalQuery.pendingDocument.contains("event"))
        #expect(ApprovalQuery.replyDocument.contains("addPullRequestReviewThreadReply"))
        #expect(ApprovalQuery.replyDocument.contains("pullRequestReviewId: $review"))
        #expect(ApprovalQuery.submitPendingDocument.contains("submitPullRequestReview"))
    }

    @Test("The review it started is read back by id")
    func readsTheReviewID() throws {
        let payload: [String: Any] = [
            "addPullRequestReview": ["pullRequestReview": ["id": "PRR_7"]]
        ]
        #expect(try ApprovalQuery.pendingReviewID(from: payload) == "PRR_7")
    }

    /// Without it the replies would be written into nothing.
    @Test("A review GitHub did not name is an error")
    func noReviewID() {
        #expect(throws: GitHubError.self) {
            try ApprovalQuery.pendingReviewID(from: ["addPullRequestReview": NSNull()])
        }
    }
}

/// Settling a conversation, and unsettling it.
@Suite("Resolving a conversation")
struct ResolveThreadTests {
    private var thread: ReviewThread {
        ReviewThread(
            id: "PRRT_1", path: "a.swift", line: 10, side: .new,
            isResolved: false, isOutdated: false,
            comments: [
                IssueComment(
                    id: "c", author: "mira", avatarURL: nil, createdAt: .now, body: "x"
                ),
            ]
        )
    }

    /// Both ways, because this is the write somebody is most likely to
    /// do by accident: a thread resolved by mistake is a question that
    /// quietly stops being asked.
    @Test("It goes both ways")
    func bothWays() {
        #expect(ResolveThreadQuery.resolveDocument.contains("resolveReviewThread"))
        #expect(ResolveThreadQuery.unresolveDocument.contains("unresolveReviewThread"))
    }

    @Test("A thread can be marked before GitHub has agreed, keeping all else")
    func marked() {
        let settled = thread.settled(true)
        #expect(settled.isResolved)
        #expect(settled.id == thread.id)
        #expect(settled.comments.count == thread.comments.count)
        #expect(settled.line == thread.line)
        #expect(!settled.settled(false).isResolved)
    }
}

/// The two things a review says about the whole pull request rather than
/// about a line of it: its own summary, and a remark for the
/// conversation tab. Both are held until the review is sent, like every
/// other box in a diff.
@Suite("What a review says about the whole")
struct WholeReviewDraftTests {
    private func draft(
        comments: [DraftComment] = [], body: String = "", conversation: String = ""
    ) -> ReviewDraft {
        ReviewDraft(
            pullRequestID: "pr-1", commit: "abc",
            comments: comments, body: body, conversation: conversation
        )
    }

    /// A review that is only a sentence about the whole is still a
    /// review. Counting it empty would have thrown it away the moment it
    /// was typed.
    @Test("A draft holding only a sentence is not empty")
    func notEmpty() {
        #expect(draft().isEmpty)
        #expect(!draft(body: "Looks right to me.").isEmpty)
        #expect(!draft(conversation: "Rebased on main.").isEmpty)
        // Whitespace is not writing.
        #expect(draft(body: "  \n ").isEmpty)
    }

    /// GitHub takes an absent body rather than an empty one: sending ""
    /// posts a review whose summary is a blank line.
    @Test("Nothing written is nothing sent")
    func nothingSent() {
        #expect(draft().writtenBody == nil)
        #expect(draft(body: "   ").writtenBody == nil)
        #expect(draft(body: "  Fine.  ").writtenBody == "Fine.")
        #expect(draft(conversation: " Rebased. ").writtenConversation == "Rebased.")
    }

    /// Somebody part way through a review when the app learned these two
    /// texts must not lose it. Bumping the schema would have been one
    /// line and would have thrown every such draft away.
    @Test("A draft written before these texts existed still reads")
    func oldDraftsSurvive() throws {
        let older = """
        {
          "schema": 1,
          "pullRequestID": "pr-1",
          "commit": "abc",
          "comments": [
            {
              "id": "7B1E5E6C-2C34-4C1C-9A2B-1D4C9F0A0001",
              "path": "a/b.swift",
              "line": 12,
              "side": "new",
              "body": "Half written.",
              "writtenAt": 780000000
            }
          ]
        }
        """
        let read = try JSONDecoder().decode(ReviewDraft.self, from: Data(older.utf8))

        #expect(read.comments.count == 1)
        #expect(read.body.isEmpty)
        #expect(read.conversation.isEmpty)
        #expect(!read.isEmpty)
    }

    /// The entry at the end of the tree is a file only so that the tree,
    /// the pager and the arrow keys reach it. Its path has to be one no
    /// repository can hold, or a real file would land on that page.
    @Test("The conversation's path is one no file can have")
    func conversationPath() {
        #expect(ChangedFile.conversation.isConversation)
        #expect(ChangedFile.conversationPath.contains("\u{0}"))
        let real = ChangedFile(
            path: "src/Filter/UserFilter.php", additions: 1, deletions: 0,
            change: .modified, patch: nil
        )
        #expect(!real.isConversation)
    }
}

/// Writing the two whole-review texts, which needs no account: they are
/// kept with the draft until one of the three review buttons sends them.
@MainActor
@Suite("Keeping what a review says about the whole")
struct WholeReviewWritingTests {
    /// A store of its own, in a directory of its own. The default one
    /// is the real folder this app keeps half-written reviews in: a test
    /// pointed at it reads whatever is in there and leaves its own
    /// behind.
    private func made() -> (AppState, RefreshController, PullRequestItem) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GitHubMonitorTests/\(UUID().uuidString)", isDirectory: true)
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        let item = PullRequestItem(
            id: "pr-1", number: 1, title: "t", repository: "octo/server", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now, reviewDecision: .none, checks: .none, headCommit: "abc"
        )
        return (
            state,
            RefreshController(state: state, draftStore: DraftStore(directory: directory)),
            item
        )
    }

    /// A review that is only a sentence about the whole still needs
    /// somewhere to live until it goes, so writing one makes a draft.
    @Test("A sentence about the whole makes a draft of its own")
    func makesADraft() {
        let (state, controller, item) = made()
        #expect(state.reviewDrafts[item.id] == nil)

        controller.setReviewBody("The locking reads right.", on: item)

        #expect(state.reviewDrafts[item.id]?.body == "The locking reads right.")
        // Bound to the commit it was written against, like the remarks.
        #expect(state.reviewDrafts[item.id]?.commit == "abc")
    }

    /// The two are separate: GitHub notifies for one as a review and for
    /// the other as a comment, and writing one must not touch the other.
    @Test("The review's words and the conversation's are kept apart")
    func keptApart() {
        let (state, controller, item) = made()

        controller.setReviewBody("Verdict.", on: item)
        controller.setConversationNote("Aside.", on: item)

        #expect(state.reviewDrafts[item.id]?.body == "Verdict.")
        #expect(state.reviewDrafts[item.id]?.conversation == "Aside.")
    }

    /// Rubbing out the last of it leaves no draft. A draft holding two
    /// empty strings would keep the window asking whether to discard an
    /// unsent review nobody wrote.
    @Test("Rubbing out the last words leaves no draft behind")
    func emptiedAway() {
        let (state, controller, item) = made()

        controller.setReviewBody("Something.", on: item)
        controller.setReviewBody("", on: item)

        #expect(state.reviewDrafts[item.id] == nil)
    }

    /// A draft with remarks in it survives its summary being rubbed out:
    /// the remarks are the review, and they were written first.
    @Test("Remarks outlive the summary being rubbed out")
    func remarksSurvive() {
        let (state, controller, item) = made()
        controller.addRemark(
            to: item, path: "a/b.swift", line: 2, side: .new, body: "Here."
        )

        controller.setReviewBody("A word.", on: item)
        controller.setReviewBody("  ", on: item)

        #expect(state.reviewDrafts[item.id]?.comments.count == 1)
        #expect(state.reviewDrafts[item.id]?.writtenBody == nil)
    }
}

/// What the three review buttons go by. Until the two whole-review
/// texts existed, "anything to send" and "remarks on lines" were the
/// same question, and the buttons asked the second one.
@Suite("Whether there is anything to send")
struct UnsentReviewTests {
    private func draft(
        comments: [DraftComment] = [], body: String = "", conversation: String = ""
    ) -> ReviewDraft {
        ReviewDraft(
            pullRequestID: "pr-1", commit: "abc",
            comments: comments, body: body, conversation: conversation
        )
    }

    private var remark: DraftComment {
        DraftComment(path: "a/b.swift", line: 3, side: .new, body: "Here.")
    }

    /// A review whose whole content is a sentence about the pull request
    /// is one somebody wrote and has every right to send. The Comment
    /// button is drawn on this, so counting only the remarks left it
    /// undrawn and the sentence unsendable.
    @Test("A sentence about the whole counts as something to send")
    func sentenceCounts() {
        #expect(draft().isEmpty)
        #expect(!draft(body: "Reads right to me.").isEmpty)
        #expect(!draft(conversation: "Rebasing on main.").isEmpty)
        #expect(!draft(comments: [remark]).isEmpty)
    }

    /// The approve button's count stays about lines. "Approve with 1
    /// remark" is a warning that something hangs on the diff, and a
    /// summary does not hang anywhere.
    @Test("The count of remarks stays about lines")
    func countStaysAboutLines() {
        #expect(draft(body: "A sentence.").comments.isEmpty)
        #expect(draft(comments: [remark], body: "A sentence.").comments.count == 1)
    }
}
