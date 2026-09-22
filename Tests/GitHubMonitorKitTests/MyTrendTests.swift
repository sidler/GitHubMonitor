import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("My trend queries")
struct MyTrendQueryTests {
    private func period(_ from: String, _ to: String) -> DateInterval {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return DateInterval(start: formatter.date(from: from)!, end: formatter.date(from: to)!)
    }

    private var week: DateInterval { period("2026-09-14 00:00", "2026-09-21 00:00") }

    @Test("The searches are scoped to the author")
    func author() {
        let opened = MyTrendQuery.openedQuery(login: "sidler", repositoryFilters: [], period: week)
        #expect(opened.contains("author:sidler"))
        #expect(opened.contains("created:2026-09-14..2026-09-20"))
        #expect(!opened.contains("is:merged"))

        let merged = MyTrendQuery.mergedQuery(login: "sidler", repositoryFilters: [], period: week)
        #expect(merged.contains("author:sidler"))
        #expect(merged.contains("is:merged"))
        #expect(merged.contains("merged:2026-09-14..2026-09-20"))
    }

    /// The charts should describe the same body of work the lists do, so
    /// they inherit the repository filters.
    @Test("Repository filters carry over from the lists")
    func filters() {
        let query = MyTrendQuery.openedQuery(
            login: "sidler",
            repositoryFilters: ["octo", "octo/platform"],
            period: week
        )
        #expect(query.contains("org:octo"))
        #expect(query.contains("repo:octo/platform"))
    }

    @Test("The document asks what is left of the hourly budget")
    func quota() {
        #expect(MyTrendQuery.document.contains("rateLimit"))
    }
}

@Suite("Reading my pull requests")
struct MyTrendPayloadTests {
    private func node(
        created: String = "2026-09-14T09:00:00Z",
        author: String = "sidler",
        comments: [[String: Any]] = [],
        commentTotal: Int? = nil,
        reviews: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "createdAt": created,
            "author": ["login": author],
            "comments": [
                "totalCount": commentTotal ?? comments.count,
                "nodes": comments,
            ],
            "reviews": ["nodes": reviews],
        ]
    }

    private func comment(by login: String, type: String = "User") -> [String: Any] {
        ["author": ["login": login, "__typename": type]]
    }

    private func review(by login: String, inline: Int, type: String = "User") -> [String: Any] {
        [
            "author": ["login": login, "__typename": type],
            "comments": ["totalCount": inline],
        ]
    }

    @Test("Conversation comments are counted and credited")
    func conversation() throws {
        let facts = try #require(
            MyTrendQuery.facts(from: node(comments: [comment(by: "dara"), comment(by: "dara")]))
        )
        #expect(facts.commentsFromEveryone == 2)
        #expect(facts.commentersFromEveryone["dara"] == 2)
    }

    /// Leaving "looks good" and leaving nine notes on the diff are not the
    /// same amount of attention.
    @Test("A review counts as one comment plus whatever it holds")
    func reviews() throws {
        let facts = try #require(
            MyTrendQuery.facts(from: node(reviews: [review(by: "mira", inline: 4)]))
        )
        #expect(facts.commentsFromEveryone == 5)
        #expect(facts.commentersFromEveryone["mira"] == 5)
    }

    /// CI writes more than colleagues do; counting it would drown them out
    /// of the ranking.
    @Test("Bots are counted apart from people")
    func bots() throws {
        let facts = try #require(
            MyTrendQuery.facts(
                from: node(
                    comments: [comment(by: "sonarqube", type: "Bot"), comment(by: "dara")],
                    reviews: [review(by: "coverage", inline: 2, type: "Bot")]
                )
            )
        )
        #expect(facts.commentsFromEveryone == 5)
        #expect(facts.commentsFromPeople == 1)
        #expect(facts.commentersFromPeople["dara"] == 1)
        #expect(facts.commentersFromPeople["sonarqube"] == nil)
        #expect(facts.commentersFromEveryone["sonarqube"] == 1)
    }

    /// The nodes stop at fifty; the total does not. A pull request with a
    /// hundred comments must still report a hundred.
    @Test("The count comes from GitHub's total, not from the fetched page")
    func truncation() throws {
        let facts = try #require(
            MyTrendQuery.facts(from: node(comments: [comment(by: "dara")], commentTotal: 120))
        )
        #expect(facts.commentsFromEveryone == 120)
    }

    /// You are in every one of your own pull requests, so counting yourself
    /// would put you at the top of the ranking and say nothing.
    @Test("Your own comments are left out")
    func ownComments() throws {
        let facts = try #require(
            MyTrendQuery.facts(
                from: node(
                    comments: [comment(by: "sidler"), comment(by: "dara"), comment(by: "sidler")],
                    reviews: [review(by: "sidler", inline: 3), review(by: "mira", inline: 1)]
                )
            )
        )
        #expect(facts.commentsFromEveryone == 3)
        #expect(facts.commentsFromPeople == 3)
        #expect(facts.commentersFromEveryone["sidler"] == nil)
        #expect(facts.commentersFromEveryone["dara"] == 1)
        #expect(facts.commentersFromEveryone["mira"] == 2)
    }

    @Test("A node without a creation date is not a data point")
    func malformed() {
        #expect(MyTrendQuery.facts(from: [:]) == nil)
    }
}

@Suite("My trend arithmetic")
struct MyTrendMathTests {
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

    private func facts(
        at created: String,
        comments: Int = 0,
        botComments: Int = 0,
        commenter: String = "dara"
    ) -> MyPullRequestFacts {
        MyPullRequestFacts(
            createdAt: date(created),
            commentsFromPeople: comments,
            commentsFromEveryone: comments + botComments,
            commentersFromPeople: comments > 0 ? [commenter: comments] : [:],
            commentersFromEveryone: comments > 0
                ? [commenter: comments, "ci": botComments]
                : ["ci": botComments]
        )
    }

    private var period: DateInterval {
        DateInterval(start: date("2026-09-14 00:00"), end: date("2026-09-21 00:00"))
    }

    @Test("The hour of day is the local hour the pull request was opened")
    func hours() {
        let bucket = TrendMath.myBucket(
            period: period,
            opened: [facts(at: "2026-09-14 09:30"), facts(at: "2026-09-15 09:45"), facts(at: "2026-09-16 22:10")],
            merged: [],
            calendar: calendar
        )
        #expect(bucket.hours[9] == 2)
        #expect(bucket.hours[22] == 1)
        #expect(bucket.hours[3] == nil)
        #expect(bucket.opened == 3)
    }

    /// The same shape as the durations: was the period even, or did one
    /// pull request carry all the discussion?
    @Test("Comments report fewest, middle and most")
    func comments() {
        let bucket = TrendMath.myBucket(
            period: period,
            opened: [
                facts(at: "2026-09-14 09:00", comments: 1),
                facts(at: "2026-09-15 09:00", comments: 4),
                facts(at: "2026-09-16 09:00", comments: 20),
            ],
            merged: [],
            calendar: calendar
        )
        let point = bucket.comments(includingBots: false)
        #expect(point.fastest == 1)
        #expect(point.median == 4)
        #expect(point.slowest == 20)
        #expect(point.samples == 3)
    }

    @Test("Commenters are summed across the period, bots kept apart")
    func commenters() {
        let bucket = TrendMath.myBucket(
            period: period,
            opened: [
                facts(at: "2026-09-14 09:00", comments: 2, botComments: 5),
                facts(at: "2026-09-15 09:00", comments: 3, botComments: 1),
            ],
            merged: [],
            calendar: calendar
        )
        #expect(bucket.commentersFromPeople["dara"] == 5)
        #expect(bucket.commentersFromPeople["ci"] == nil)
        #expect(bucket.commentersFromEveryone["ci"] == 6)
    }

    /// A single period holds far too few pull requests to say anything
    /// about habits; the shape only appears across the range.
    @Test("The range sums the periods for the hours and the commenters")
    func acrossTheRange() {
        let first = TrendMath.myBucket(
            period: period,
            opened: [facts(at: "2026-09-14 09:00", comments: 2)],
            merged: [],
            calendar: calendar
        )
        let second = TrendMath.myBucket(
            period: period,
            opened: [facts(at: "2026-09-21 09:00", comments: 3)],
            merged: [],
            calendar: calendar
        )
        let data = MyTrendData(login: "sidler", resolution: .weekly, buckets: [first, second])

        #expect(data.hours[9] == 2)
        #expect(data.totalOpened == 2)
        #expect(data.commenters(includingBots: false).first?.login == "dara")
        #expect(data.commenters(includingBots: false).first?.comments == 5)
    }

    /// Ties would otherwise reorder themselves on every redraw.
    @Test("Commenters with the same count keep a stable order")
    func stableRanking() {
        let bucket = TrendMath.myBucket(
            period: period,
            opened: [
                facts(at: "2026-09-14 09:00", comments: 3, commenter: "zoe"),
                facts(at: "2026-09-15 09:00", comments: 3, commenter: "adam"),
            ],
            merged: [],
            calendar: calendar
        )
        let data = MyTrendData(login: "sidler", resolution: .weekly, buckets: [bucket])
        #expect(data.commenters(includingBots: false).map(\.login) == ["adam", "zoe"])
    }

    @Test("A period with nothing in it reports nothing rather than zero")
    func empty() {
        let bucket = TrendMath.myBucket(period: period, opened: [], merged: [], calendar: calendar)
        #expect(bucket.opened == 0)
        #expect(bucket.hours.isEmpty)
        #expect(bucket.comments(includingBots: false).median == nil)
        #expect(bucket.merge.median == nil)
    }

    @Test("Merge times come from the pull requests merged in the period")
    func merges() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bucket = TrendMath.myBucket(
            period: period,
            opened: [],
            merged: [
                PullRequestTiming(
                    isBot: false, readyAt: start, mergedAt: start.addingTimeInterval(3_600),
                    firstReviewAt: nil, lastApprovalAt: nil
                ),
                PullRequestTiming(
                    isBot: false, readyAt: start, mergedAt: start.addingTimeInterval(7_200),
                    firstReviewAt: nil, lastApprovalAt: nil
                ),
            ],
            calendar: calendar
        )
        #expect(bucket.merge.median == 5_400)
        #expect(bucket.merge.samples == 2)
        // Opened and merged describe different pull requests, so a period
        // can report merges without having opened anything.
        #expect(bucket.opened == 0)
    }
}

@MainActor
@Suite("My trend cache")
struct MyTrendStoreTests {
    private func store() -> (TrendStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("githubmonitor-tests-\(UUID().uuidString)")
        return (TrendStore(directory: directory), directory)
    }

    private func data(login: String = "sidler") -> MyTrendData {
        MyTrendData(
            login: login,
            resolution: .weekly,
            buckets: [
                MyTrendBucket(
                    start: Date(timeIntervalSince1970: 1_700_000_000),
                    end: Date(timeIntervalSince1970: 1_700_604_800),
                    opened: 3,
                    hours: [9: 2, 17: 1],
                    commentsFromPeople: TrendPoint(median: 4, fastest: 1, slowest: 9, samples: 3),
                    commentsFromEveryone: TrendPoint(median: 6, fastest: 2, slowest: 14, samples: 3),
                    commentersFromPeople: ["dara": 7],
                    commentersFromEveryone: ["dara": 7, "ci": 5],
                    merge: TrendPoint(median: 3_600, fastest: 600, slowest: 9_000, samples: 2)
                ),
            ]
        )
    }

    @Test("What was written comes back")
    func roundTrip() throws {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(data())
        let loaded = try #require(store.loadMine(login: "sidler", resolution: .weekly))
        #expect(loaded.buckets.first?.hours[9] == 2)
        #expect(loaded.buckets.first?.commentersFromPeople["dara"] == 7)
        #expect(loaded.buckets.first?.merge.median == 3_600)
    }

    /// Two people on one machine, or a repository and a login: neither may
    /// be drawn as the other.
    @Test("A history belongs to the account it was read for")
    func otherAccount() {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(data(login: "sidler"))
        #expect(store.loadMine(login: "mira", resolution: .weekly) == nil)
        #expect(store.loadMine(login: "sidler", resolution: .monthly) == nil)
        // A repository history and a personal one must not collide.
        #expect(store.load(repository: "sidler", resolution: .weekly) == nil)
    }
}

@Suite("Chart axis labels")
struct TrendAxisTests {
    /// Zero is a tick on every linear axis, and the logarithm of it is
    /// infinite: turning that into a number of decimal places crashed the
    /// app the first time this view was opened.
    @Test("Zero and nonsense do not bring the axis down")
    func zero() {
        #expect(TrendAxis.number(0) == "0")
        #expect(TrendAxis.number(-5) == "0")
        #expect(TrendAxis.number(.infinity) == "0")
        #expect(TrendAxis.number(.nan) == "0")
    }

    @Test("Values are written with as many decimals as they need")
    func decimals() {
        #expect(TrendAxis.number(1000) == "1000")
        #expect(TrendAxis.number(1) == "1")
        #expect(TrendAxis.number(0.1) == "0.1")
        #expect(TrendAxis.number(0.001) == "0.001")
    }

    @Test("Decades run from one to the largest value, at most five of them")
    func decades() {
        #expect(TrendAxis.decades([5, 500], enabled: true) == [1, 10, 100, 1000])
        #expect(TrendAxis.decades([0.5], enabled: true).isEmpty)
        #expect(TrendAxis.decades([5], enabled: false).isEmpty)
        #expect(TrendAxis.decades([.infinity], enabled: true).isEmpty)
        #expect(TrendAxis.decades([1e9], enabled: true).count <= 5)
    }
}
