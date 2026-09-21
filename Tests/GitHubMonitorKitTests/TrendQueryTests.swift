import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Trend queries")
struct TrendQueryTests {
    private func period(_ from: String, _ to: String) -> DateInterval {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return DateInterval(start: formatter.date(from: from)!, end: formatter.date(from: to)!)
    }

    /// A period ends at the first instant of the next one, while GitHub's
    /// ranges include both ends: off by one here and every Sunday's merges
    /// land in the following week.
    @Test("The search range stops on the period's last day")
    func range() {
        let query = TrendQuery.mergedQuery(
            repository: "octo/platform",
            period: period("2026-09-14 00:00", "2026-09-21 00:00")
        )
        #expect(query.contains("merged:2026-09-14..2026-09-20"))
        #expect(query.contains("repo:octo/platform"))
        #expect(query.contains("is:merged"))
    }

    /// The volume chart asks how much work arrived, not how much landed.
    @Test("The opened query does not ask for merged pull requests")
    func openedQuery() {
        let query = TrendQuery.openedQuery(
            repository: "octo/platform",
            period: period("2026-09-14 00:00", "2026-09-21 00:00")
        )
        #expect(query.contains("created:2026-09-14..2026-09-20"))
        #expect(!query.contains("is:merged"))
    }

    @Test("Both documents ask what is left of the hourly budget")
    func quota() {
        #expect(TrendQuery.mergedDocument.contains("rateLimit"))
        #expect(TrendQuery.openedDocument.contains("rateLimit"))
    }

    /// The counting query fetches authors and nothing else: a period with
    /// hundreds of pull requests should stay cheap.
    @Test("The counting query asks for no nested data")
    func openedDocumentIsCheap() {
        #expect(!TrendQuery.openedDocument.contains("reviews"))
        #expect(!TrendQuery.openedDocument.contains("timelineItems"))
        #expect(TrendQuery.openedDocument.contains("__typename"))
    }
}

@Suite("Reading trend payloads")
struct TrendPayloadTests {
    private func node(
        created: String = "2026-09-01T09:00:00Z",
        merged: String? = "2026-09-03T09:00:00Z",
        author: String = "mira",
        authorType: String = "User",
        readyAt: String? = nil,
        reviews: [[String: Any]] = []
    ) -> [String: Any] {
        var node: [String: Any] = [
            "createdAt": created,
            "author": ["login": author, "__typename": authorType],
            "reviews": ["nodes": reviews],
        ]
        if let merged { node["mergedAt"] = merged }
        if let readyAt {
            node["timelineItems"] = ["nodes": [["createdAt": readyAt]]]
        }
        return node
    }

    private func review(
        _ state: String,
        at: String,
        by login: String = "dara",
        type: String = "User"
    ) -> [String: Any] {
        ["state": state, "submittedAt": at, "author": ["login": login, "__typename": type]]
    }

    private func date(_ string: String) -> Date {
        GitHubDate.optional(from: string)!
    }

    @Test("A merged pull request yields its timestamps")
    func timing() throws {
        let raw = node(reviews: [
            review("COMMENTED", at: "2026-09-01T15:00:00Z"),
            review("APPROVED", at: "2026-09-02T09:00:00Z"),
        ])
        let timing = try #require(TrendQuery.timing(from: raw))
        #expect(timing.readyAt == date("2026-09-01T09:00:00Z"))
        #expect(timing.firstReviewAt == date("2026-09-01T15:00:00Z"))
        #expect(timing.lastApprovalAt == date("2026-09-02T09:00:00Z"))
        #expect(timing.mergedAt == date("2026-09-03T09:00:00Z"))
        #expect(!timing.isBot)
    }

    /// A pull request that lay three days as a draft was not waiting on
    /// anybody for those three days.
    @Test("The clock starts when the draft was marked ready")
    func readyForReview() throws {
        let raw = node(
            created: "2026-09-01T09:00:00Z",
            readyAt: "2026-09-04T09:00:00Z",
            reviews: [review("APPROVED", at: "2026-09-04T12:00:00Z")]
        )
        let timing = try #require(TrendQuery.timing(from: raw))
        #expect(timing.readyAt == date("2026-09-04T09:00:00Z"))
        #expect(timing.timeToFirstReview == 10_800)
    }

    /// Reviews left while it was still a draft belong to the draft.
    @Test("A review from before it was ready does not count")
    func reviewBeforeReady() throws {
        let raw = node(
            readyAt: "2026-09-04T09:00:00Z",
            reviews: [
                review("COMMENTED", at: "2026-09-02T09:00:00Z"),
                review("APPROVED", at: "2026-09-04T11:00:00Z"),
            ]
        )
        let timing = try #require(TrendQuery.timing(from: raw))
        #expect(timing.firstReviewAt == date("2026-09-04T11:00:00Z"))
    }

    /// CI bots post reviews. Counting them would measure the pipeline's
    /// latency and call it attention from a colleague.
    @Test("A bot's review is not a review")
    func botReview() throws {
        let raw = node(reviews: [
            review("COMMENTED", at: "2026-09-01T09:05:00Z", by: "sonarqube", type: "Bot"),
            review("APPROVED", at: "2026-09-02T09:00:00Z"),
        ])
        let timing = try #require(TrendQuery.timing(from: raw))
        #expect(timing.firstReviewAt == date("2026-09-02T09:00:00Z"))
    }

    @Test("The author reviewing their own pull request is not a review")
    func selfReview() throws {
        let raw = node(reviews: [
            review("COMMENTED", at: "2026-09-01T10:00:00Z", by: "mira"),
            review("APPROVED", at: "2026-09-02T09:00:00Z"),
        ])
        let timing = try #require(TrendQuery.timing(from: raw))
        #expect(timing.firstReviewAt == date("2026-09-02T09:00:00Z"))
    }

    /// The last approval, not the first: that is the point from which only
    /// the merge was outstanding, and it is what makes the three intervals
    /// add up.
    @Test("The last approval before the merge is the one that counts")
    func lastApproval() throws {
        let raw = node(reviews: [
            review("APPROVED", at: "2026-09-01T12:00:00Z", by: "a"),
            review("CHANGES_REQUESTED", at: "2026-09-01T14:00:00Z", by: "b"),
            review("APPROVED", at: "2026-09-02T18:00:00Z", by: "b"),
        ])
        let timing = try #require(TrendQuery.timing(from: raw))
        #expect(timing.lastApprovalAt == date("2026-09-02T18:00:00Z"))
    }

    @Test("A pull request with no merge date is not a data point")
    func unmerged() {
        #expect(TrendQuery.timing(from: node(merged: nil)) == nil)
        // Search results include entries that are not pull requests at all.
        #expect(TrendQuery.timing(from: [:]) == nil)
    }

    @Test("GitHub's own bot flag decides what a bot is")
    func botAuthor() throws {
        let raw = node(author: "renovate", authorType: "Bot")
        let timing = try #require(TrendQuery.timing(from: raw))
        #expect(timing.isBot)
    }

    @Test("A page reports its cursor only while there is more to fetch")
    func paging() {
        let more: [String: Any] = [
            "search": [
                "nodes": [],
                "pageInfo": ["hasNextPage": true, "endCursor": "Y3Vyc29y"],
            ],
            "rateLimit": ["remaining": 4_812],
        ]
        let page = TrendQuery.mergedPage(from: more)
        #expect(page.cursor == "Y3Vyc29y")
        #expect(page.remainingQuota == 4_812)

        let done: [String: Any] = [
            "search": ["nodes": [], "pageInfo": ["hasNextPage": false, "endCursor": "Y3Vyc29y"]],
        ]
        #expect(TrendQuery.mergedPage(from: done).cursor == nil)
    }

    @Test("The counting page separates people from bots")
    func openedPage() {
        let payload: [String: Any] = [
            "search": [
                "nodes": [
                    ["author": ["__typename": "User"]],
                    ["author": ["__typename": "Bot"]],
                    ["author": ["__typename": "User"]],
                ],
                "pageInfo": ["hasNextPage": false],
            ],
        ]
        let page = TrendQuery.openedPage(from: payload)
        #expect(page.items.count == 3)
        #expect(page.items.count { $0 } == 1)
    }
}

@Suite("Trend cache")
struct TrendStoreTests {
    private func store() -> (TrendStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("githubmonitor-tests-\(UUID().uuidString)")
        return (TrendStore(directory: directory), directory)
    }

    private func data(
        repository: String = "octo/platform",
        resolution: TrendResolution = .weekly,
        fetchedAt: Date = .now
    ) -> TrendData {
        TrendData(
            repository: repository,
            resolution: resolution,
            buckets: [
                TrendBucket(
                    start: Date(timeIntervalSince1970: 1_700_000_000),
                    end: Date(timeIntervalSince1970: 1_700_604_800),
                    people: TrendValues(
                        opened: 4, merged: 3,
                        firstReview: TrendPoint(median: 3_600, fastest: 600, slowest: 9_000, samples: 3),
                        approval: TrendPoint(median: 7_200, fastest: 7_200, slowest: 7_200, samples: 2),
                        approvalToMerge: TrendPoint(median: 1_800, fastest: 60, slowest: 3_600, samples: 2),
                        merge: TrendPoint(median: 9_000, fastest: 900, slowest: 20_000, samples: 3)
                    ),
                    everyone: .none
                ),
            ],
            fetchedAt: fetchedAt
        )
    }

    @Test("What was written comes back")
    func roundTrip() throws {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(data())
        let loaded = try #require(store.load(repository: "octo/platform", resolution: .weekly))
        #expect(loaded.buckets.first?.people.firstReview.median == 3_600)
        #expect(loaded.buckets.first?.people.firstReview.fastest == 600)
        #expect(loaded.buckets.first?.people.firstReview.slowest == 9_000)
        #expect(loaded.buckets.first?.people.opened == 4)
    }

    /// A history written before a definition changed would go on being
    /// drawn as though it had not; the version is what stops that.
    @Test("A history from an older schema is not read")
    func schema() throws {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(data())
        let url = store.url(repository: "octo/platform", resolution: .weekly)
        let raw = try #require(try? Data(contentsOf: url))
        let aged = String(decoding: raw, as: UTF8.self)
            .replacingOccurrences(of: "\"schema\":\(TrendData.schema)", with: "\"schema\":1")
        try aged.data(using: .utf8)?.write(to: url)

        #expect(store.load(repository: "octo/platform", resolution: .weekly) == nil)
    }

    /// Weeks and months are different fetches; keeping both means switching
    /// between them shows the other straight away.
    @Test("Each repository and resolution has its own file")
    func separateFiles() {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(data(resolution: .weekly))
        #expect(store.load(repository: "octo/platform", resolution: .monthly) == nil)
        #expect(store.load(repository: "octo/other", resolution: .weekly) == nil)
    }

    /// A repository name is a path of its own, and must not become one.
    @Test("The owner's slash does not turn into a directory")
    func slug() {
        #expect(TrendStore.slug("octo/platform") == "octo-platform")
        #expect(!TrendStore.slug("../../etc/passwd").contains("/"))
    }

    @Test("A history older than six hours counts as stale")
    func staleness() {
        #expect(!data(fetchedAt: .now).isStale)
        #expect(data(fetchedAt: .now.addingTimeInterval(-7 * 3600)).isStale)
    }

    @Test("Nothing stored means nothing loaded, rather than an empty chart")
    func missing() {
        let (store, _) = store()
        #expect(store.load(repository: "octo/platform", resolution: .weekly) == nil)
    }
}
