import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("How long a review took to answer")
struct ReviewResponseTests {
    private func date(_ iso: String) -> Date { GitHubDate.date(from: iso) }

    private func node(
        requests: [(login: String?, team: String?, at: String)],
        reviews: [String]
    ) -> [String: Any] {
        var events: [[String: Any]] = []
        for request in requests {
            var reviewer: [String: Any] = [:]
            if let login = request.login { reviewer["login"] = login }
            if let team = request.team { reviewer["name"] = team }
            events.append(["createdAt": request.at, "requestedReviewer": reviewer])
        }
        return [
            "timelineItems": ["nodes": events],
            "reviews": ["nodes": reviews.map { ["submittedAt": $0] }],
        ]
    }

    @Test("From the request to the first review after it")
    func firstRound() throws {
        let response = try #require(MyTrendQuery.response(
            from: node(
                requests: [(login: "sidler", team: nil, at: "2026-09-01T09:00:00Z")],
                reviews: ["2026-09-01T15:00:00Z"]
            ),
            viewer: "sidler"
        ))
        #expect(response.duration == 6 * 3600)
    }

    /// Later rounds are quick by nature -- the reviewer already knows the
    /// change -- so counting them would flatter the figure.
    @Test("Only the first round counts")
    func onlyFirstRound() throws {
        let response = try #require(MyTrendQuery.response(
            from: node(
                requests: [
                    (login: "sidler", team: nil, at: "2026-09-01T09:00:00Z"),
                    (login: "sidler", team: nil, at: "2026-09-05T09:00:00Z"),
                ],
                reviews: ["2026-09-02T09:00:00Z", "2026-09-05T09:30:00Z"]
            ),
            viewer: "sidler"
        ))
        #expect(response.duration == 24 * 3600)
    }

    /// A review left before anyone asked -- someone reading a colleague's
    /// work unprompted -- is not an answer to the request that followed.
    @Test("A review before the request does not count as the answer")
    func reviewBeforeRequest() throws {
        let response = try #require(MyTrendQuery.response(
            from: node(
                requests: [(login: "sidler", team: nil, at: "2026-09-03T09:00:00Z")],
                reviews: ["2026-09-01T09:00:00Z", "2026-09-04T09:00:00Z"]
            ),
            viewer: "sidler"
        ))
        #expect(response.duration == 24 * 3600)
    }

    @Test("Asked but never answered is not a measurement")
    func neverAnswered() {
        #expect(MyTrendQuery.response(
            from: node(
                requests: [(login: "sidler", team: nil, at: "2026-09-01T09:00:00Z")],
                reviews: []
            ),
            viewer: "sidler"
        ) == nil)
    }

    @Test("Answered without ever being asked by name is not a measurement")
    func neverAsked() {
        #expect(MyTrendQuery.response(
            from: node(
                requests: [(login: nil, team: "Frontend", at: "2026-09-01T09:00:00Z")],
                reviews: ["2026-09-02T09:00:00Z"]
            ),
            viewer: "sidler"
        ) == nil)
    }

    @Test("A page carries its rows, its cursor and the budget left")
    func page() {
        let payload: [String: Any] = [
            "rateLimit": ["remaining": 4321, "cost": 1],
            "search": [
                "pageInfo": ["hasNextPage": true, "endCursor": "abc"],
                "nodes": [
                    node(
                        requests: [(login: "sidler", team: nil, at: "2026-09-01T09:00:00Z")],
                        reviews: ["2026-09-01T10:00:00Z"]
                    ),
                    // Not answered: dropped rather than counted as zero.
                    node(
                        requests: [(login: "sidler", team: nil, at: "2026-09-02T09:00:00Z")],
                        reviews: []
                    ),
                ],
            ],
        ]
        let page = MyTrendQuery.responsePage(from: payload, viewer: "sidler")
        #expect(page.items.count == 1)
        #expect(page.items.first?.duration == 3600)
        #expect(page.cursor == "abc")
        #expect(page.remainingQuota == 4321)
    }

    @Test("The search asks for the pull requests you reviewed")
    func query() {
        let period = DateInterval(
            start: GitHubDate.date(from: "2026-09-01T00:00:00Z"),
            end: GitHubDate.date(from: "2026-09-30T00:00:00Z")
        )
        let query = MyTrendQuery.reviewedQuery(
            login: "sidler", repositoryFilters: ["octo"], period: period
        )
        #expect(query.contains("is:pr"))
        #expect(query.contains("reviewed-by:sidler"))
        #expect(query.contains("org:octo"))
    }

    /// The bucket is what the chart reads; an empty period must be a gap in
    /// the line rather than a zero anybody could mistake for speed.
    @Test("A period nobody asked you about has no point")
    func emptyPeriod() {
        let period = DateInterval(start: .now.addingTimeInterval(-86400), duration: 86400)
        let bucket = TrendMath.myBucket(period: period, opened: [], merged: [], responses: [])
        #expect(bucket.response.median == nil)
        #expect(bucket.response.samples == 0)
    }

    @Test("A period's median, fastest and slowest come from its answers")
    func filledPeriod() {
        let period = DateInterval(start: .now.addingTimeInterval(-86400), duration: 86400)
        // One fixed instant for all three: two separate calls to `.now`
        // differ by microseconds, which is enough to miss an exact hour.
        let asked = Date(timeIntervalSince1970: 1_800_000_000)
        let responses = [1.0, 3.0, 9.0].map {
            ReviewResponse(requestedAt: asked, respondedAt: asked.addingTimeInterval($0 * 3600))
        }
        let bucket = TrendMath.myBucket(
            period: period, opened: [], merged: [], responses: responses
        )
        // Double literals rather than `3 * 3600`: inside `#expect`, an
        // optional Double compared against an integer-literal product comes
        // out false even though plain Swift says true. Checked in isolation
        // before writing it this way.
        #expect(bucket.response.median == 10800.0)
        #expect(bucket.response.fastest == 3600.0)
        #expect(bucket.response.slowest == 32400.0)
        #expect(bucket.response.samples == 3)
    }
}
