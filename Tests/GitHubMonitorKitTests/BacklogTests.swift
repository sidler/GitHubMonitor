import Foundation
import Testing

@testable import GitHubMonitorKit

/// What stood open at a moment, and how much of it was draft.
@Suite("Backlog")
struct BacklogTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    private func at(_ days: Double) -> Date { start.addingTimeInterval(days * day) }

    private func pullRequest(
        _ key: String = "1",
        bot: Bool = false,
        created: Double = 0,
        closed: Double? = nil,
        draftNow: Bool = false,
        changes: [(Double, Bool)] = [],
        closings: [(Double, Bool)] = []
    ) -> BacklogPullRequest {
        BacklogPullRequest(
            key: key,
            isBot: bot,
            createdAt: at(created),
            closedAt: closed.map(at),
            isDraft: draftNow,
            draftChanges: changes.map { DraftChange(at: at($0.0), toDraft: $0.1) },
            closeChanges: closings.map { CloseChange(at: at($0.0), toClosed: $0.1) }
        )
    }

    /// A period's end is the first instant of the next one, so both ends
    /// are measured against it as an exclusive upper bound: created at the
    /// stroke of it belongs to the next period, closed at the stroke of it
    /// was open for the whole of this one. Measured the other way round, a
    /// pull request opened and closed on two boundaries was credited to
    /// exactly the two periods it was not open in.
    @Test("Open from the moment it was created until the moment it closed")
    func openWindow() {
        let item = pullRequest(created: 2, closed: 5)

        #expect(item.wasOpen(at: at(1)) == false)
        #expect(item.wasOpen(at: at(2)) == false)
        #expect(item.wasOpen(at: at(3)))
        #expect(item.wasOpen(at: at(4)))
        #expect(item.wasOpen(at: at(5)))
        #expect(item.wasOpen(at: at(6)) == false)
    }

    /// `closedAt` is set back to null when a pull request is reopened, so
    /// it is no record of the closed stretch at all. Taken at face value a
    /// pull request closed in April and reopened in September read as
    /// having been open since the day it was made -- confirmed against
    /// artemeon/core-ng#36892, which is OPEN with a null closedAt and a
    /// ReopenedEvent.
    @Test("A reopened pull request was shut in between")
    func reopened() {
        let item = pullRequest(created: 0, closed: nil, closings: [(3, true), (8, false)])

        #expect(item.wasOpen(at: at(2)))
        #expect(item.wasOpen(at: at(4)) == false)
        #expect(item.wasOpen(at: at(7)) == false)
        #expect(item.wasOpen(at: at(9)))
        #expect(item.wasOpen(at: at(100)))
    }

    /// A merge files a ClosedEvent beside its MergedEvent, so one kind of
    /// event covers both ways of going away.
    @Test("One closed and left closed stays closed")
    func closedForGood() {
        let item = pullRequest(created: 0, closed: 4, closings: [(4, true)])

        #expect(item.wasOpen(at: at(3)))
        #expect(item.wasOpen(at: at(4)))
        #expect(item.wasOpen(at: at(5)) == false)
    }

    /// The events are read newest-first and may not reach back to the
    /// beginning, so before the oldest one the current state is all there
    /// is to go on.
    @Test("Before the first recorded move it was whatever it is now")
    func beforeTheEvents() {
        let stillOpen = pullRequest(created: 0, closed: nil, closings: [(5, true), (6, false)])
        #expect(stillOpen.wasOpen(at: at(2)))

        let closedNow = pullRequest(created: 0, closed: 9, closings: [])
        #expect(closedNow.wasOpen(at: at(2)))
        #expect(closedNow.wasOpen(at: at(20)) == false)
    }

    @Test("One never closed is open ever after")
    func stillOpen() {
        let item = pullRequest(created: 2)

        #expect(item.wasOpen(at: at(2)) == false)
        #expect(item.wasOpen(at: at(3)))
        #expect(item.wasOpen(at: at(400)))
    }

    /// GitHub's search can say a pull request is a draft now; it cannot say
    /// it was one in March. Counting today's flag backwards would show a
    /// draft pile that grows towards the present purely because the older
    /// drafts have since been marked ready.
    @Test("Draft state is replayed, not read off today's flag")
    func draftHistory() {
        // Opened as a draft, marked ready on day three.
        let item = pullRequest(created: 0, draftNow: false, changes: [(3, false)])

        #expect(item.wasDraft(at: at(1)))
        #expect(item.wasDraft(at: at(3)) == false)
        #expect(item.wasDraft(at: at(10)) == false)
    }

    @Test("A pull request put back into draft counts as one again")
    func backToDraft() {
        let item = pullRequest(
            created: 0,
            draftNow: true,
            changes: [(2, false), (6, true)]
        )

        // Before the first event it was the opposite of what that event
        // produced: the first move made it ready, so until then it was a
        // draft.
        #expect(item.wasDraft(at: at(1)))
        #expect(item.wasDraft(at: at(4)) == false)
        #expect(item.wasDraft(at: at(7)))
    }

    @Test("One that never changed has always been what it is now")
    func neverChanged() {
        #expect(pullRequest(draftNow: true).wasDraft(at: at(5)))
        #expect(pullRequest(draftNow: false).wasDraft(at: at(5)) == false)
    }

    /// Order comes from the timestamps rather than from the page GitHub
    /// happened to return them on.
    @Test("Changes are read in time order whatever order they arrived in")
    func unsortedChanges() {
        let item = pullRequest(created: 0, draftNow: true, changes: [(6, true), (2, false)])

        #expect(item.wasDraft(at: at(1)))
        #expect(item.wasDraft(at: at(4)) == false)
        #expect(item.wasDraft(at: at(7)))
    }

    /// Drafts are counted inside the open total, not beside it: a draft is
    /// an open pull request, and two lines adding up to more than the
    /// repository has would be read as a third number nobody meant.
    @Test("Drafts are part of the open count")
    func draftsAreOpen() {
        let counted = BacklogMath.count(
            [
                pullRequest("1", created: 0, draftNow: true),
                pullRequest("2", created: 0),
                pullRequest("3", created: 0, closed: 1),
            ],
            at: at(2)
        )

        #expect(counted.open == 2)
        #expect(counted.draft == 1)
    }

    @Test("Nothing created yet counts for nothing")
    func beforeAnything() {
        let counted = BacklogMath.count([pullRequest(created: 4)], at: at(1))

        #expect(counted == (0, 0))
    }
}

/// How the standing count is asked for, given that GitHub can only answer
/// about now.
@Suite("Asking what stood open")
struct BacklogQueryTests {
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Pull requests created and closed inside the same period were never
    /// open at any boundary, so they belong to no bar -- and in a busy
    /// repository they are most of what was created.
    /// `TrendQuery.range` writes bare days in the reader's own time zone
    /// and GitHub reads a bare day as UTC, while the counting asks about
    /// `period.end` to the second. The two windows disagree by the
    /// offset, so the asking errs outward and the counting does the rest.
    @Test("A period asks for a day more than it needs, and excludes a day less")
    func periodQuery() {
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let period = DateInterval(start: start, end: start.addingTimeInterval(30 * 86_400))
        let written = BacklogQuery.query(repository: "octo/platform", period: period)

        #expect(written.contains("repo:octo/platform is:pr"))
        let wanted = TrendQuery.range(BacklogQuery.padded(period, byDays: 1)!)
        let inner = TrendQuery.range(BacklogQuery.padded(period, byDays: -1)!)
        #expect(written.contains("created:\(wanted)"))
        #expect(written.contains("-closed:\(inner)"))
        // Outward for what is asked for, inward for what is excluded --
        // the other way round would drop the rows in the gap.
        #expect(wanted != TrendQuery.range(period))
        #expect(inner != TrendQuery.range(period))
    }

    /// A period too short to narrow does not try: the exclusion is only
    /// ever an optimisation, and an inverted range would exclude the lot.
    @Test("A period shorter than two days excludes nothing")
    func shortPeriod() {
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let period = DateInterval(start: start, end: start.addingTimeInterval(3600))
        let written = BacklogQuery.query(repository: "octo/platform", period: period)

        #expect(written.contains("created:"))
        #expect(written.contains("-closed:") == false)
    }

    /// Without this the first bars would count only what the window itself
    /// created, and a backlog older than the chart would appear to grow out
    /// of nothing.
    @Test("The window opens with whatever was already standing")
    func openingQuery() {
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let written = BacklogQuery.openingQuery(repository: "octo/platform", before: start)

        // Padded the same way and for the same reason as a period's.
        #expect(written.contains("created:<\(formatter.string(from: start.addingTimeInterval(86_400)))"))
        #expect(
            written.contains("-closed:<\(formatter.string(from: start.addingTimeInterval(-86_400)))")
        )
    }

    /// The newest moves, not the oldest: the bars anybody reads are the
    /// recent ones, and asked the other way round a pull request with more
    /// moves than the limit had its state decided by an event from months
    /// ago.
    @Test("The timeline is read from the recent end")
    func recentEnd() {
        #expect(BacklogQuery.document.contains("last: \(BacklogQuery.events)"))
        #expect(BacklogQuery.document.contains("first: \(BacklogQuery.events)") == false)
        #expect(BacklogQuery.document.contains("CLOSED_EVENT"))
        #expect(BacklogQuery.document.contains("REOPENED_EVENT"))
    }

    @Test("A pull request is read with its dates and its draft moves")
    func reading() {
        let node: [String: Any] = [
            "id": "PR_1",
            "createdAt": "2026-03-01T10:00:00Z",
            "closedAt": "2026-03-09T10:00:00Z",
            "isDraft": false,
            "author": ["__typename": "User"],
            "timelineItems": [
                "nodes": [
                    ["__typename": "ReadyForReviewEvent", "createdAt": "2026-03-03T10:00:00Z"],
                    ["__typename": "ConvertToDraftEvent", "createdAt": "2026-03-05T10:00:00Z"],
                    ["__typename": "ClosedEvent", "createdAt": "2026-03-07T10:00:00Z"],
                    ["__typename": "ReopenedEvent", "createdAt": "2026-03-08T10:00:00Z"],
                ]
            ],
        ]

        let read = BacklogQuery.pullRequest(from: node)

        // The one timeline carries two histories and they are told apart.
        #expect(read?.closeChanges.map(\.toClosed) == [true, false])

        #expect(read?.key == "PR_1")
        #expect(read?.isBot == false)
        #expect(read?.draftChanges.count == 2)
        #expect(read?.draftChanges.first?.toDraft == false)
        #expect(read?.draftChanges.last?.toDraft == true)
        #expect(read?.wasOpen(at: GitHubDate.optional(from: "2026-03-04T10:00:00Z")!) == true)
        #expect(read?.wasDraft(at: GitHubDate.optional(from: "2026-03-02T10:00:00Z")!) == true)
        #expect(read?.wasDraft(at: GitHubDate.optional(from: "2026-03-04T10:00:00Z")!) == false)
        #expect(read?.wasDraft(at: GitHubDate.optional(from: "2026-03-06T10:00:00Z")!) == true)
    }

    /// The chart's bot switch has to work without another trip to GitHub,
    /// so who opened it travels with the rest.
    @Test("A bot's pull request is marked as one")
    func bots() {
        let node: [String: Any] = [
            "id": "PR_2",
            "createdAt": "2026-03-01T10:00:00Z",
            "isDraft": true,
            "author": ["__typename": "Bot"],
            "timelineItems": ["nodes": []],
        ]

        #expect(BacklogQuery.pullRequest(from: node)?.isBot == true)
    }

    @Test("A node without an id is not a pull request")
    func rubbish() {
        #expect(BacklogQuery.pullRequest(from: ["createdAt": "2026-03-01T10:00:00Z"]) == nil)
    }

    /// Both bars come out of one set of pull requests, measured at the end
    /// of the period rather than at its start.
    @Test("A bucket counts what stood open when the period ended")
    func bucket() {
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let period = DateInterval(start: start, end: start.addingTimeInterval(30 * 86_400))

        let bucket = TrendMath.bucket(
            period: period,
            merged: [],
            openedByPeople: 0,
            openedByEveryone: 0,
            backlog: [
                // Open throughout, a draft the whole time.
                BacklogPullRequest(
                    key: "1", isBot: false, createdAt: start,
                    closedAt: nil, isDraft: true
                ),
                // Closed inside the period, so it left nothing behind.
                BacklogPullRequest(
                    key: "2", isBot: false, createdAt: start,
                    closedAt: start.addingTimeInterval(86_400), isDraft: false
                ),
                // A bot's, which only the second audience counts.
                BacklogPullRequest(
                    key: "3", isBot: true, createdAt: start,
                    closedAt: nil, isDraft: false
                ),
            ]
        )

        #expect(bucket.people.open == 1)
        #expect(bucket.people.draft == 1)
        #expect(bucket.everyone.open == 2)
        #expect(bucket.everyone.draft == 1)
    }
}
