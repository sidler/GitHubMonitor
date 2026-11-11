import Foundation
import Testing

@testable import GitHubMonitorKit

/// How far down the notification stream a poll reaches, and how it finds
/// its way there.
@Suite("Asking for the unread notifications")
struct NotificationQueryTests {
    // MARK: Following GitHub's own cursor

    /// The header as GitHub actually sends it, copied from a live answer.
    private let header = """
        <https://api.github.com/notifications?all=false&per_page=50&page=2>; rel="next", \
        <https://api.github.com/notifications?all=false&per_page=50&page=52>; rel="last"
        """

    @Test("The next page is the one GitHub named next, not the last")
    func next() {
        let found = NotificationQuery.next(from: header)

        #expect(found?.absoluteString.contains("page=2") == true)
        #expect(found?.absoluteString.contains("page=52") == false)
    }

    /// The last page carries prev and first and no next, and that is how
    /// the walk knows to stop.
    @Test("No next link is the end of the walk")
    func lastPage() {
        let last = """
            <https://api.github.com/notifications?page=51>; rel="prev", \
            <https://api.github.com/notifications?page=1>; rel="first"
            """

        #expect(NotificationQuery.next(from: last) == nil)
        #expect(NotificationQuery.next(from: nil) == nil)
        #expect(NotificationQuery.next(from: "") == nil)
    }

    /// A repository-scoped stream is handed back under a numeric path that
    /// was never asked for, which is the reason the link is followed as
    /// given rather than rebuilt from a page number.
    @Test("The link is followed as given, whatever path it names")
    func foreignPath() {
        let moved = """
            <https://api.github.com/repositories/260475222/notifications?page=2>; rel="next"
            """

        #expect(
            NotificationQuery.next(from: moved)?.absoluteString
                == "https://api.github.com/repositories/260475222/notifications?page=2"
        )
    }

    /// `rel=next` turns up unquoted and spaced differently by different
    /// servers, and a parser that only knows one spelling stops walking
    /// after the first page without saying why.
    @Test("rel=next is recognised however it is spelled")
    func spellings() {
        for variant in [
            "<https://x/n?page=2>; rel=\"next\"",
            "<https://x/n?page=2>;rel=next",
            "<https://x/n?page=2>; rel=next",
            "<https://x/n?page=1>; rel=\"prev\", <https://x/n?page=2>; rel=\"next\"",
        ] {
            #expect(NotificationQuery.next(from: variant)?.absoluteString == "https://x/n?page=2")
        }
    }

    // MARK: What is asked for

    /// Fifty is GitHub's own ceiling for this endpoint: asking for a
    /// hundred returns fifty. Pinned because the number reads like a
    /// choice and is not one.
    @Test("The page size is the one GitHub will actually serve")
    func pageSize() {
        let url = NotificationQuery.first(participating: false).absoluteString

        #expect(url.contains("per_page=50"))
        #expect(url.contains("all=false"))
        #expect(url.contains("participating") == false)
    }

    @Test("Participating is asked for only when it is asked for")
    func participatingParameter() {
        #expect(
            NotificationQuery.first(participating: true).absoluteString
                .contains("participating=true")
        )
    }

    // MARK: When the saving is safe

    /// Threads from watched repositories are what `participating=true`
    /// removes, and on a busy account they are half the stream. Somebody
    /// who wants them must not have them dropped.
    @Test("Wanting watched repositories rules the shortcut out")
    func subscribedRulesItOut() {
        #expect(NotificationQuery.participating(for: [.mention]))
        #expect(NotificationQuery.participating(for: [.mention, .subscribed]) == false)
    }

    /// The cautious half. A mention of a team is not the reader
    /// participating, and GitHub's own wording suggests it goes with the
    /// watched repositories -- so where team mentions are wanted, the
    /// whole stream is read rather than risking a list that is quietly
    /// empty. They are on by default, which is what makes the risk worth
    /// avoiding.
    @Test("Wanting team mentions rules the shortcut out too")
    func teamMentionsRuleItOut() {
        #expect(NotificationQuery.participating(for: [.mention, .teamMention]) == false)
    }

    /// Read off a fresh install rather than written out here, because it
    /// is the default that makes this worth being careful about: most
    /// people never touch these boxes, and the shortcut must not quietly
    /// empty their list.
    @MainActor
    @Test("A fresh install takes the safe path")
    func shippedDefault() {
        let settings = Settings(store: TestDefaults.make())

        #expect(settings.notificationReasons.contains(.teamMention))
        #expect(NotificationQuery.participating(for: settings.notificationReasons) == false)
    }

    @Test("Wanting nothing at all still asks safely")
    func noReasons() {
        #expect(NotificationQuery.participating(for: []))
    }

    // MARK: Saying when it stopped

    @Test("A walk stopped at the cap says so")
    func truncation() {
        let note = NotificationQuery.truncationNote(pages: NotificationQuery.pageCap)

        #expect(note.contains("\(NotificationQuery.pageCap)"))
        #expect(!note.isEmpty)
    }

    /// The cap has to be past the stream of a busy account or it is not a
    /// cap, it is the bug again with a message attached. The one this was
    /// measured against ran to 52 pages unfiltered and 25 with
    /// `participating=true`.
    @Test("The cap clears a busy account's filtered stream")
    func capIsRoomy() {
        #expect(NotificationQuery.pageCap >= 25)
        #expect(NotificationQuery.pageCap * NotificationQuery.pageSize >= 1200)
    }
}
