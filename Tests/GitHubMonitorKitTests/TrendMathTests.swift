import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Trend periods")
struct TrendPeriodTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    @Test("Twelve periods, oldest first, ending with the current one")
    func shape() throws {
        let periods = TrendMath.periods(.weekly, reference: date("2026-09-21 10:00"), calendar: calendar)
        #expect(periods.count == 12)
        #expect(periods == periods.sorted { $0.start < $1.start })
        let last = try #require(periods.last)
        #expect(last.contains(date("2026-09-21 10:00")))
    }

    /// ISO weeks, so a week runs Monday to Sunday -- a Sunday merge belongs
    /// to the week that is ending, not the one about to start.
    @Test("Weeks start on Monday")
    func weekStart() throws {
        let periods = TrendMath.periods(.weekly, reference: date("2026-09-21 10:00"), calendar: calendar)
        let last = try #require(periods.last)
        #expect(calendar.component(.weekday, from: last.start) == 2)
        #expect(last.contains(date("2026-09-21 00:30")))
        #expect(!last.contains(date("2026-09-20 23:30")))
    }

    @Test("Months are calendar months")
    func months() throws {
        let periods = TrendMath.periods(.monthly, reference: date("2026-09-21 10:00"), calendar: calendar)
        #expect(periods.count == 12)
        let last = try #require(periods.last)
        #expect(last.contains(date("2026-09-01 00:30")))
        #expect(!last.contains(date("2026-08-31 23:30")))
        // A year back, so the first period is the same month last year.
        #expect(calendar.component(.month, from: periods[0].start) == 10)
    }
}

@Suite("Trend arithmetic")
struct TrendMathTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func timing(
        isBot: Bool = false,
        ready: TimeInterval = 0,
        firstReview: TimeInterval? = nil,
        approval: TimeInterval? = nil,
        merged: TimeInterval
    ) -> PullRequestTiming {
        PullRequestTiming(
            isBot: isBot,
            readyAt: start.addingTimeInterval(ready),
            mergedAt: start.addingTimeInterval(merged),
            firstReviewAt: firstReview.map(start.addingTimeInterval),
            lastApprovalAt: approval.map(start.addingTimeInterval)
        )
    }

    @Test("The four durations are measured from ready for review")
    func durations() throws {
        let item = timing(ready: 100, firstReview: 3_700, approval: 7_300, merged: 10_900)
        #expect(item.timeToFirstReview == 3_600)
        #expect(item.timeToApproval == 7_200)
        #expect(item.approvalToMerge == 3_600)
        #expect(item.timeToMerge == 10_800)
    }

    /// The whole point of anchoring on the last approval: the three
    /// intervals have to add up, or the four charts contradict each other.
    @Test("Time to approval plus approval to merge is time to merge")
    func additive() throws {
        let item = timing(firstReview: 500, approval: 4_000, merged: 9_000)
        let toApproval = try #require(item.timeToApproval)
        let toMerge = try #require(item.approvalToMerge)
        #expect(toApproval + toMerge == item.timeToMerge)
    }

    @Test("A stage that never happened has no duration, rather than zero")
    func missingStages() {
        let never = timing(merged: 9_000)
        #expect(never.timeToFirstReview == nil)
        #expect(never.timeToApproval == nil)
        #expect(never.approvalToMerge == nil)
        #expect(never.timeToMerge == 9_000)
    }

    /// Events out of order mean the assumption behind the measurement does
    /// not hold; a zero would be indistinguishable from an instant review.
    @Test("An interval that runs backwards is dropped")
    func backwards() {
        let odd = timing(ready: 5_000, firstReview: 1_000, merged: 9_000)
        #expect(odd.timeToFirstReview == nil)
    }

    @Test("The median is the middle value, or the mean of the middle two")
    func median() {
        #expect(TrendMath.median([3, 1, 2]) == 2)
        #expect(TrendMath.median([4, 1, 2, 3]) == 2.5)
        #expect(TrendMath.median([7]) == 7)
        #expect(TrendMath.median([]) == nil)
    }

    /// One forgotten pull request must not move the number the chart shows.
    @Test("An outlier does not drag the median")
    func outlier() {
        let normal: [TimeInterval] = [3_600, 3_700, 3_800]
        #expect(TrendMath.median(normal) == 3_700)
        #expect(TrendMath.median(normal + [2_000_000]) == 3_750)
    }

    @Test("A period counts only the pull requests that reached each stage")
    func samples() {
        let values = TrendMath.values(
            merged: [
                timing(firstReview: 3_600, approval: 7_200, merged: 10_800),
                timing(firstReview: 1_800, merged: 5_400),
                timing(merged: 900),
            ],
            opened: 9
        )
        #expect(values.merged == 3)
        #expect(values.opened == 9)
        #expect(values.firstReview.samples == 2)
        #expect(values.approval.samples == 1)
        #expect(values.merge.samples == 3)
        #expect(values.firstReview.median == 2_700)
    }

    /// Both audiences come out of the same fetch, so hiding the bots is a
    /// redraw rather than another trip to GitHub.
    @Test("Bots are counted apart, not thrown away")
    func bots() {
        let bucket = TrendMath.bucket(
            period: DateInterval(start: start, duration: 86_400),
            merged: [
                timing(firstReview: 3_600, merged: 7_200),
                timing(isBot: true, firstReview: 60, merged: 120),
            ],
            openedByPeople: 4,
            openedByEveryone: 11
        )
        #expect(bucket.people.merged == 1)
        #expect(bucket.everyone.merged == 2)
        #expect(bucket.people.opened == 4)
        #expect(bucket.everyone.opened == 11)
        #expect(bucket.people.firstReview.median == 3_600)
        #expect(bucket.everyone.firstReview.median == 1_830)
        #expect(bucket.values(includingBots: false) == bucket.people)
    }

    @Test("An empty period reports nothing rather than zero")
    func emptyPeriod() {
        let values = TrendMath.values(merged: [], opened: 0)
        #expect(values.firstReview.median == nil)
        #expect(values.firstReview.samples == 0)
        #expect(values.merged == 0)
    }

    /// First reviews land in hours, merges in days: one scale for both
    /// would flatten three of the four curves into the axis.
    @Test("The unit follows the size of the series")
    func units() {
        #expect(TrendMath.unit(for: [600, 1_200]) == .minutes)
        #expect(TrendMath.unit(for: [7_200, 20_000]) == .hours)
        #expect(TrendMath.unit(for: [200_000]) == .days)
        #expect(TrendMath.unit(for: []) == .hours)
    }

    @Test("Durations read the way a person would say them")
    func wording() {
        #expect(TrendMath.describe(45) == "45s")
        #expect(TrendMath.describe(600) == "10m")
        #expect(TrendMath.describe(3_600) == "1h")
        #expect(TrendMath.describe(5_400) == "1h 30m")
        #expect(TrendMath.describe(3 * 86_400) == "3.0 days")
    }
}
