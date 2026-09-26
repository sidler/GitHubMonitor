import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Relative dates in a search")
struct RelativeDateTests {
    /// A fixed point to stand on, in a calendar that does not move under
    /// the test: 20 September 2026, UTC.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 14))!
    }

    private func expand(_ query: String) -> String {
        RelativeDates.expand(query, now: now, calendar: calendar)
    }

    /// The case that sent us here: written the way the browser accepts it,
    /// rejected by the search API with "not a recognized date/time format".
    @Test("A week back becomes the date GitHub asks for")
    func weekBack() {
        #expect(
            expand("is:pr author:@me state:closed closed:>@today-1w repo:octo/platform")
                == "is:pr author:@me state:closed closed:>2026-09-13 repo:octo/platform"
        )
    }

    @Test("A bare @today is today")
    func bare() {
        #expect(expand("closed:>@today") == "closed:>2026-09-20")
    }

    @Test(
        "Days, weeks, months and years all count",
        arguments: [
            ("@today-3d", "2026-09-17"),
            ("@today-2w", "2026-09-06"),
            ("@today-1m", "2026-08-20"),
            ("@today-1y", "2025-09-20"),
            ("@today+5d", "2026-09-25"),
        ]
    )
    func units(written: String, expected: String) {
        #expect(expand(written) == expected)
    }

    @Test("The unit may be written in capitals")
    func capitals() {
        #expect(expand("@TODAY-1W") == "2026-09-13")
    }

    @Test("Several in one line are all resolved")
    func several() {
        #expect(
            expand("created:>@today-1m closed:<@today-1d")
                == "created:>2026-08-20 closed:<2026-09-19"
        )
    }

    /// The expansion must not reach into words that merely end in the same
    /// letters.
    @Test("A word ending in today is left alone")
    func notAWord() {
        #expect(expand("label:not@today") == "label:not@today")
        #expect(expand("branch/fix-today") == "branch/fix-today")
    }

    @Test("A query with no relative date comes back untouched")
    func untouched() {
        let query = "is:pr review-requested:@me archived:false"
        #expect(expand(query) == query)
        #expect(!RelativeDates.mentionsRelativeDate(query))
    }

    @Test("An offset with no unit is read as a plain @today")
    func offsetWithoutUnit() {
        // "@today-1" has no unit, so only the `@today` part matches and the
        // rest stays as written rather than being silently swallowed.
        #expect(expand("closed:>@today-1") == "closed:>2026-09-20-1")
    }

    /// The arithmetic and the formatting have to happen in the same
    /// calendar, or an evening east of Greenwich reports yesterday.
    @Test("The date is formatted in the calendar it was worked out in")
    func sameCalendar() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // 22:30 in Berlin is still the 20th there, and already the 20th at
        // 20:30 UTC -- the point is that the answer follows the calendar it
        // was given.
        let evening = berlin.date(
            from: DateComponents(year: 2026, month: 9, day: 20, hour: 22, minute: 30)
        )!
        #expect(RelativeDates.expand("@today", now: evening, calendar: berlin) == "2026-09-20")
    }
}

@Suite("Searches carry resolved dates")
struct SearchExpansionTests {
    @Test("A list's search is sent with the date written out")
    func listSearch() {
        let list = SavedList(
            id: "recent", title: "Recently closed",
            query: "is:pr author:@me state:closed closed:>@today-1w repo:octo/platform",
            content: .pullRequests
        )
        let searches = ListQuery.searches(for: list, repositoryFilters: [])
        let sent = searches.first?.query ?? ""

        #expect(!sent.contains("@today"))
        #expect(sent.contains("closed:>"))
        // `@me` is GitHub's own and must survive untouched.
        #expect(sent.contains("author:@me"))
    }
}
