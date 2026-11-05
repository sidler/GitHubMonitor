import Foundation
import Testing

@testable import GitHubMonitorKit

/// Who does the reviewing, and how long the rest of the team waits on
/// them.
@Suite("Reviewer figures")
struct ReviewerStatsTests {
    private let day: TimeInterval = 86_400
    private let hour: TimeInterval = 3600
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func pullRequest(
        _ key: String,
        closed: TimeInterval? = 10 * 86_400,
        asked: [(String, TimeInterval)] = [],
        reviewed: [(String, TimeInterval)] = [],
        stillAsked: Set<String>? = nil,
        by author: String? = nil
    ) -> ReviewedPullRequest {
        ReviewedPullRequest(
            key: key,
            closedAt: closed.map { start.addingTimeInterval($0) },
            author: author,
            requests: asked.map {
                RequestedReview(reviewer: $0.0, at: start.addingTimeInterval($0.1))
            },
            reviews: reviewed.map {
                SubmittedReview(reviewer: $0.0, at: start.addingTimeInterval($0.1))
            },
            // By default everybody asked is still on the list, which is
            // the ordinary case: somebody was asked and the question
            // stood until it was answered.
            stillRequested: stillAsked ?? Set(asked.map(\.0))
        )
    }

    private func stats(
        _ pullRequests: [ReviewedPullRequest], for reviewer: String
    ) -> ReviewerStats? {
        ReviewerStatsMath.summarise(pullRequests).first { $0.reviewer == reviewer }
    }

    /// Three rounds of comments on one pull request is one pull request
    /// read. Counting it as three would flatter whoever argues most.
    @Test("Several reviews of one pull request are one pull request")
    func distinctPullRequests() {
        let found = stats(
            [
                pullRequest("1", reviewed: [("ada", 0), ("ada", hour), ("ada", 2 * hour)]),
                pullRequest("2", reviewed: [("ada", 0)]),
            ],
            for: "ada"
        )

        #expect(found?.pullRequests == 2)
        #expect(found?.reviews == 4)
    }

    /// GitHub files a remark on your own pull request as a review. It is
    /// not code you read, and counting it would have people reviewing
    /// themselves to the top of the ranking.
    @Test("Your own pull requests are not pull requests you reviewed")
    func ownPullRequests() {
        let found = ReviewerStatsMath.summarise([
            pullRequest("1", reviewed: [("ada", 0), ("bob", 0)], by: "ada"),
            pullRequest("2", reviewed: [("ada", 0)], by: "bob"),
        ])

        let ada = found.first { $0.reviewer == "ada" }
        #expect(ada?.pullRequests == 1)
        #expect(ada?.reviews == 1)

        // Bob reviewed one that was not his, and it still counts.
        #expect(found.first { $0.reviewer == "bob" }?.pullRequests == 1)
    }

    @Test("The wait is from being asked to answering")
    func wait() {
        let found = stats(
            [pullRequest("1", asked: [("ada", 0)], reviewed: [("ada", 3 * hour)])],
            for: "ada"
        )

        #expect(found?.answered == 1)
        #expect(found?.median == 3 * hour)
        #expect(found?.mean == 3 * hour)
    }

    /// A review submitted before the request answers nothing -- somebody
    /// read it unasked, and the request that came afterwards is still
    /// outstanding.
    /// A request that was withdrawn, or one left behind by a re-request
    /// after the person had already answered, is not an unanswered
    /// question -- nobody was waiting on it. Counting those put
    /// colleagues at a quarter ignored when the truth was a twentieth.
    @Test("A request nobody is waiting on any more is not ignored")
    func withdrawnRequest() {
        let withdrawn = stats(
            [pullRequest("1", asked: [("ada", 0)], stillAsked: [])],
            for: "ada"
        )
        // Nothing happened that is worth a row: no review, no answer, and
        // no question left standing.
        #expect(withdrawn == nil)

        // The same request, still standing at the close, is ignored.
        let standing = stats([pullRequest("1", asked: [("ada", 0)])], for: "ada")
        #expect(standing?.ignored == 1)
    }

    @Test("A review before the request does not answer it")
    func reviewBeforeRequest() {
        let found = stats(
            [pullRequest("1", asked: [("ada", 2 * hour)], reviewed: [("ada", hour)])],
            for: "ada"
        )

        #expect(found?.answered == 0)
        #expect(found?.ignored == 1)
        // It still counts as a pull request they read.
        #expect(found?.pullRequests == 1)
        #expect(found?.reviews == 1)
    }

    /// Being asked again after a round of changes is a second wait, and
    /// the team feels it as keenly as the first.
    @Test("Each request is answered at most once")
    func repeatedRequests() {
        let found = stats(
            [
                pullRequest(
                    "1",
                    asked: [("ada", 0), ("ada", 4 * hour)],
                    reviewed: [("ada", hour), ("ada", 5 * hour)]
                )
            ],
            for: "ada"
        )

        #expect(found?.answered == 2)
        #expect(found?.median == hour)
    }

    /// Nobody was waiting on it any more. It is not a slow answer, it is
    /// no answer.
    @Test("A request still open when the pull request closed was ignored")
    func ignored() {
        let found = stats([pullRequest("1", asked: [("ada", 0)])], for: "ada")

        #expect(found?.ignored == 1)
        #expect(found?.pending == 0)
        #expect(found?.median == nil)
    }

    /// The clock on these has not stopped, so they are neither kept nor
    /// ignored yet.
    @Test("A request on a pull request that is still open is pending")
    func pending() {
        let found = stats([pullRequest("1", closed: nil, asked: [("ada", 0)])], for: "ada")

        #expect(found?.pending == 1)
        #expect(found?.ignored == 0)
    }

    /// Out of the settled requests only, or somebody would look worse the
    /// busier the repository is this week.
    @Test("The ignored share leaves the still-open requests out of it")
    func ignoredShare() {
        let found = stats(
            [
                pullRequest("1", asked: [("ada", 0)], reviewed: [("ada", hour)]),
                pullRequest("2", asked: [("ada", 0)], reviewed: [("ada", hour)]),
                pullRequest("3", asked: [("ada", 0)], reviewed: [("ada", hour)]),
                pullRequest("4", asked: [("ada", 0)]),
                pullRequest("5", closed: nil, asked: [("ada", 0)]),
            ],
            for: "ada"
        )

        #expect(found?.answered == 3)
        #expect(found?.ignored == 1)
        #expect(found?.pending == 1)
        #expect(found?.ignoredShare == 0.25)
    }

    /// Nearest rank: the ninetieth percentile of ten answers is the ninth
    /// of them, a number somebody actually waited.
    @Test("The ninetieth percentile is an answer somebody actually waited")
    func percentile() {
        let values = (1...10).map { Double($0) * hour }

        #expect(ReviewerStatsMath.percentile(values, 0.9) == 9 * hour)
        #expect(ReviewerStatsMath.percentile(values, 0.5) == 5 * hour)
        #expect(ReviewerStatsMath.percentile([], 0.9) == nil)
        #expect(ReviewerStatsMath.percentile([hour], 0.9) == hour)
    }

    /// A median of an hour with a ninetieth of ten days is a different
    /// person from one with a ninetieth of an hour, which is the whole
    /// reason the tail is reported beside the middle.
    @Test("The slow tail is reported beside the middle")
    func tail() {
        let quick = (0..<8).map {
            pullRequest("q\($0)", asked: [("ada", 0)], reviewed: [("ada", hour)])
        }
        let slow = (0..<2).map {
            pullRequest("s\($0)", asked: [("ada", 0)], reviewed: [("ada", 10 * day)])
        }

        let found = stats(quick + slow, for: "ada")

        #expect(found?.median == hour)
        #expect(found?.p90 == 10 * day)
    }

    /// One slow answer in ten is below the ninetieth, and the figure says
    /// so rather than being dragged up by it. That is what nearest rank
    /// is for, and what the mean beside it is not.
    @Test("A single slow answer in ten does not move the ninetieth")
    func lonelyTail() {
        let quick = (0..<9).map {
            pullRequest("q\($0)", asked: [("ada", 0)], reviewed: [("ada", hour)])
        }
        let slow = pullRequest("s", asked: [("ada", 0)], reviewed: [("ada", 10 * day)])

        let found = stats(quick + [slow], for: "ada")

        #expect(found?.p90 == hour)
        // The mean does move, which is why both are shown.
        #expect((found?.mean ?? 0) > 20 * hour)
    }

    @Test("Busiest first, by pull requests read")
    func volumeOrder() {
        let all = ReviewerStatsMath.byVolume(
            ReviewerStatsMath.summarise([
                pullRequest("1", reviewed: [("ada", 0), ("bob", 0)]),
                pullRequest("2", reviewed: [("ada", 0)]),
            ])
        )

        #expect(all.map(\.reviewer) == ["ada", "bob"])
    }

    /// Somebody who has never answered a request has no time to rank, and
    /// putting them at either end of a list about speed would say
    /// something the data does not.
    @Test("The speed ranking leaves out anybody with nothing to measure")
    func speedOrder() {
        let all = ReviewerStatsMath.bySpeed(
            ReviewerStatsMath.summarise([
                pullRequest("1", asked: [("ada", 0)], reviewed: [("ada", 2 * hour)]),
                pullRequest("2", asked: [("bob", 0)], reviewed: [("bob", 5 * day)]),
                // Asked, never answered, pull request closed.
                pullRequest("3", asked: [("cat", 0)]),
            ])
        )

        #expect(all.map(\.reviewer) == ["bob", "ada"])
    }
}

/// How the window is asked about, given that one search hands back a
/// thousand results and says nothing when it has more.
@Suite("Asking about a window of reviewing")
struct ReviewerStatsSlicingTests {
    private let day: TimeInterval = 86_400

    @Test("The window is cut into months")
    func months() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let slices = ReviewerStatsQuery.slices(since: now.addingTimeInterval(-90 * day), now: now)

        // Three or four, depending on where in the month it starts. The
        // property worth asserting is that the window is covered, not how
        // the calendar happened to fall.
        #expect(slices.count >= 3)
        #expect(slices.first!.start <= now.addingTimeInterval(-89 * day))
        #expect(slices.last!.end == now)
    }

    /// Inclusive at both ends is how GitHub reads a range, so the pieces
    /// have to stop the day before the next begins or a pull request
    /// updated on the boundary is counted twice.
    @Test("The pieces do not overlap")
    func disjoint() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let slices = ReviewerStatsQuery.slices(since: now.addingTimeInterval(-200 * day), now: now)

        let written = slices.map {
            ReviewerStatsQuery.query(repository: "octo/platform", range: $0)
        }
        #expect(Set(written).count == written.count)
        for (earlier, later) in zip(slices, slices.dropFirst()) {
            #expect(earlier.end <= later.start)
        }
    }

    /// A window shorter than a month is still a window.
    @Test("A few days is one piece")
    func shortWindow() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let slices = ReviewerStatsQuery.slices(since: now.addingTimeInterval(-3 * day), now: now)

        #expect(slices.count == 1)
    }
}
